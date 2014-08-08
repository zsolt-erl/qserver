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

-record(state, {
        listensocket,
        acceptor,
        queue_workers = []   :: [pid()],
        session_workers = [] :: [pid()],
        active_sessions = [] :: {Qworker :: pid(), Sworker::pid(), Socket::pid()}
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
    {ok, ListenSocket} = gen_tcp:listen(?PORT, [{ip, {0,0,0,0}}, list, {packet, line}]),
    Self = self(),
    ?log("Listening on: ~p", [?PORT]),
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
handle_info({'DOWN', _Ref, process, Acceptor, _Reason}, State = #state{acceptor = Acceptor}) ->
    ?log("Acceptor process went down, respawning it"),
    NewAcceptor = spawn(?MODULE, acceptor, [self()]),
    erlang:monitor(process, NewAcceptor),
    NewState = State#state{acceptor = NewAcceptor},
    {noreply, NewState};

handle_info({new_connection, Socket}, State = #state{session_workers = Sworkers, queue_workers = Qworkers, active_sessions = ActiveSessions}) ->
    %% get a session worker
    %% get a queue worker
    %% pass Socket to session worker
    %% create active ssn record (PIDs of workers and socket)

    ?log("got new connection"),
    QworkerCount = length(Qworkers) + length(ActiveSessions),
    {NewQworker, NewQueueWorkers} = case Qworkers of
        %% grab an idle worker
        [Hq|Tq] -> {Hq, Tq};
        
        %% no idle workers, create a new one
        [] when QworkerCount < 5 ->
            {ok, QW} = queue_sup:start_child(),
            erlang:monitor(process, QW),
            {QW, []};

        %% can't assign worker
        _ -> throw(no_more_queues)
    end,

    SworkerCount = length(Sworkers) + length(ActiveSessions),
    {NewSworker, NewSessionWorkers} = case Sworkers of
        %% grab an idle worker
        [Hs|Ts] -> {Hs, Ts};
        
        %% no idle workers, create a new one
        [] when SworkerCount < 5 ->
            {ok, SW} = session_sup:start_child(NewQworker),
            erlang:monitor(process, SW),
            {SW, []};

        %% can't assign worker
        _ -> throw(no_more_sessions)
    end,


    NewActiveSessions = [{NewSworker, NewQworker, Socket} | ActiveSessions],

    %% give the socket to the new session worker
    gen_tcp:controlling_process(Socket, NewSworker),

    NewState = State#state{session_workers = NewSessionWorkers, queue_workers = NewQueueWorkers, active_sessions = NewActiveSessions},
    {noreply, NewState};

handle_info({session_worker, Pid, tcp_closed}, State = #state{session_workers = Sworkers, queue_workers = Qworkers, active_sessions = ActiveSessions}) ->
    %% remove session worker and queue worker from active sessions
    %% reset queue
    %% add worker PIDs to the pools in State
    {noreply, State};

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


