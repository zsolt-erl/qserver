-module(session_mngr).

-include("qserver.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0]).

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
    %%NewAcceptor = spawn(?MODULE, acceptor, [self()]),
    %%erlang:monitor(process, NewAcceptor),
    %%NewState = State#state{acceptor = NewAcceptor},
    {noreply, State};

handle_info({new_connection, _Socket}, State) ->
    ?log("got new connection"),
    %% get a session worker
    %% get a queue worker
    %% pass Socket to session worker
    %% create active ssn record (PIDs of workers and socket)
    NewState = State,
    {noreply, NewState};

handle_info(Info, State) ->
    ?log("SSN MNGR received: ~p", [Info]),
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


