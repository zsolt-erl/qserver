-module(session_mngr).

-include("qserver.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0, get_state/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(session, {
        qworker :: pid(),
        sworker :: pid(),
        socket  :: port()
}).

-record(state, {
        listensocket,
        acceptor,
        queue_workers = []   :: [pid()],
        session_workers = [] :: [pid()],
        active_sessions = [] :: [#session{}]
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_state() ->
    gen_server:call(?MODULE, get_state).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    {ok, ListenSocket} = gen_tcp:listen(?conf(bind_port), [{ip, ?conf(bind_ip)}, list, {packet, line}]),
    Self = self(),
    ?log("Listening on: ~p", [?conf(bind_port)]),
    Acceptor = spawn(fun()->acceptor(ListenSocket, Self) end),
    erlang:monitor(process, Acceptor),
    {ok, #state{listensocket = ListenSocket, acceptor = Acceptor}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(get_state, _From, State) ->
    Reply = State,
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

%% session worker started
handle_info({Pid, session_worker_ready}, State = #state{session_workers = Sworkers, active_sessions = ActiveSessions}) ->
    monitor(process, Pid),
    NewState = 
        case lists:keyfind(Pid, #session.sworker, ActiveSessions) of
            false ->
                %% not in active session, add to list of session workers
                State#state{session_workers = [Pid|Sworkers]};
            _ -> 
                State
        end,
    {noreply, NewState};

%% queue worker started
handle_info({Pid, queue_worker_ready}, State = #state{queue_workers = Qworkers, active_sessions = ActiveSessions}) ->
    monitor(process, Pid),
    NewState = 
        case lists:keyfind(Pid, #session.qworker, ActiveSessions) of
            false ->
                %% not in active session, add to list of session workers
                State#state{queue_workers = [Pid|Qworkers]};
            _ -> 
                State
        end,
    {noreply, NewState};

%% connection acceptor process died
handle_info({'DOWN', _Ref, process, Acceptor, _Reason}, State = #state{acceptor = Acceptor}) ->
    ?log("Acceptor process went down, respawning it"),
    NewAcceptor = spawn(?MODULE, acceptor, [self()]),
    erlang:monitor(process, NewAcceptor),
    NewState = State#state{acceptor = NewAcceptor},
    {noreply, NewState};

%% some other process died (session worker or queue worker)
handle_info({'DOWN', _Ref, process, Pid, Reason}, State = #state{session_workers = Sworkers, queue_workers = Qworkers, active_sessions = ActiveSessions}) ->
    %% TODO: ugly cascading case; figure out how to refactor it!
    %% check if it was an idle session worker
    NewState = case lists:member(Pid, Sworkers) of
        true  -> State#state{session_workers = Sworkers -- [Pid]};
        false -> 
            %% idle queue worker?
            case lists:member(Pid, Qworkers) of
                true  -> State#state{queue_workers = Qworkers -- [Pid]};
                false -> 
                    %% active session worker?
                    case lists:keytake(Pid, #session.sworker, ActiveSessions) of 
                        {value, Session, NewActiveSessions} ->
                            %% reset the queue and return it to idle pool since the session worker crashed
                            queue_worker:reset(Session#session.qworker),
                            NewQworkers = [Session#session.qworker | Qworkers],
                            State#state{queue_workers = NewQworkers, active_sessions = NewActiveSessions};
                        false -> 
                            %% active queue worker?
                            case lists:keytake(Pid, #session.qworker, ActiveSessions) of 
                                {value, Session, NewActiveSessions} ->
                                    %% reset the session worker and return it to idle pool since the queue worker crashed
                                    session_worker:reset(Session#session.sworker),
                                    NewSworkers = [Session#session.sworker | Sworkers],
                                    State#state{session_workers = NewSworkers, active_sessions = NewActiveSessions};
                                false ->
                                    %% no idea who this was, don't do anything just log it
                                    ?log("some unknown process (~p) crashed with reason: ~p", [Pid, Reason]),
                                    State
                            end
                    end
            end
    end,
    {noreply, NewState};

handle_info({new_connection, Socket}, State) ->
    ?log("got new connection"),

    try
        NewState = set_up_session(Socket, State),
        gen_tcp:send(Socket, "connected to qserver\r\n" ), 
        {noreply, NewState}
    catch
        throw:Term ->
            ?log("closing connection: ~p", [Term]),
            gen_tcp:send(Socket, io_lib:format("~p\r\n", [Term]) ), 
            gen_tcp:close(Socket),
            {noreply, State}
    end;

handle_info({session_worker, SWpid, tcp_closed}, State = #state{session_workers = Sworkers, queue_workers = Qworkers, active_sessions = ActiveSessions}) ->
    %% remove session worker and queue worker from active sessions
    %% reset queue
    %% add worker PIDs to the pools in State
    {NewSworkers, NewQworkers, NewActiveSessions} = 
        case lists:keytake(SWpid, #session.sworker, ActiveSessions) of
            false ->
                ?log("session worker ~p (inactive) lost connection", [SWpid]),
                {Sworkers, Qworkers, ActiveSessions};
            {value, #session{sworker = SWpid, qworker = QWpid}, RemainingSessions} ->
                ?log("session worker ~p lost connection", [SWpid]),
                queue_worker:reset(QWpid),
                session_worker:reset(SWpid),
                {[SWpid|Sworkers], [QWpid|Qworkers], RemainingSessions}
        end,
    NewState = State#state{session_workers = NewSworkers, queue_workers = NewQworkers, active_sessions = NewActiveSessions},
    {noreply, NewState};

handle_info(Info, State) ->
    ?log("received: ~p", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%%

%% accept connections and pass them over to session manager
acceptor(ListenSocket, SocketMngrPid) -> 
    ?log("Acceptor ~p is waiting for connection, ~p", [self(), SocketMngrPid]),
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} -> 
            ?log("Accepted connection"),
            ?MODULE ! {new_connection, Socket},
            ok = gen_tcp:controlling_process(Socket, SocketMngrPid);
        {error, Reason} ->
            ?log("ERROR: could not accept connection: ~p", [Reason])
    end,
    acceptor(ListenSocket, SocketMngrPid).


%% set up a new session
%% 
%% there's a 1 to 1 relation between sessions (connections) and queues
%%
-spec set_up_session(Socket :: port(), State :: #state{}) -> NewState :: #state{} .
set_up_session(Socket, State = #state{session_workers = Sworkers, queue_workers = Qworkers, active_sessions = ActiveSessions}) ->
    %% get a queue worker (create one if there's no idle, throw exception if limit is reached)
    %% get a session worker (create one if there's no idle, throw exception if limit is reached)
    %% give TCP socket to the session worker
    %% update state

    %% get a queue worker
    QworkerCount = length(Qworkers) + length(ActiveSessions),
    {NewQworker, NewQueueWorkers} = case Qworkers of
        %% grab an idle worker
        [Hq|Tq] -> {Hq, Tq};
        
        %% no idle workers
        [] -> case QworkerCount < ?conf(max_queues) of 
                %% create a new one
                true -> 
                    {ok, QW} = queue_sup:start_child(),
                    {QW, []};
                %% can't create more -> throw in the towel
                false ->
                    throw(no_available_queues)
            end
    end,

    %% get a session worker
    SworkerCount = length(Sworkers) + length(ActiveSessions),
    {NewSworker, NewSessionWorkers} = case Sworkers of
        %% grab an idle worker
        [Hs|Ts] -> {Hs, Ts};
        
        %% no idle workers
        [] -> case SworkerCount < ?conf(max_sessions) of
                true ->
                    {ok, SW} = session_sup:start_child(),
                    {SW, []};
                false ->
                    throw(no_available_sessions)
            end
    end,

    NewActiveSessions = [#session{sworker = NewSworker, qworker = NewQworker, socket = Socket} | ActiveSessions],

    %% give the socket to the new session worker and set up worker state
    gen_tcp:controlling_process(Socket, NewSworker),
    session_worker:set_socket(NewSworker, Socket),
    session_worker:set_queue(NewSworker, NewQworker),

    State#state{session_workers = NewSessionWorkers, queue_workers = NewQueueWorkers, active_sessions = NewActiveSessions}.
