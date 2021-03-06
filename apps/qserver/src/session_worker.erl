%% session worker process
%%
%% this handles the communication over an open TCP connection
%%
%% it implements the protocol that the qserver application uses to communicate over the socket connection
%%


-module(session_worker).

-include("qserver.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0, reset/1, set_queue/2, set_socket/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
        socket   :: port(),
        qworker  :: pid()
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
    gen_server:start_link(?MODULE, [], []).

%% reset the session worker, remove connection to any queue worker process
reset(Sworker) ->
    gen_server:call(Sworker, reset).

%% set up session worker to manage the Qworker queue
set_queue(Sworker, Qworker) ->
    gen_server:call(Sworker, {set_queue, Qworker}).

set_socket(Sworker, Socket) ->
    gen_server:call(Sworker, {set_socket, Socket}).

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
    ?log("(~p) initialized", [self()]),
    session_mngr ! {self(), session_worker_ready},
    {ok, #state{}}.

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

handle_call(reset, _From, State) ->
    ?log("(~p) resetting", [self()]),
    gen_tcp:close(State#state.socket),
    Reply = ok,
    {reply, Reply, State#state{qworker = undefined, socket = undefined}};

handle_call({set_queue, Qworker}, _From, State) ->
    ?log("(~p) setting queue worker to ~p", [self(), Qworker]),
    Reply = ok,
    {reply, Reply, State#state{qworker = Qworker}};

handle_call({set_socket, Socket}, _From, State) ->
    ?log("(~p) setting socket to ~p", [self(), Socket]),
    Reply = ok,
    {reply, Reply, State#state{socket = Socket}};

handle_call(Request, _From, State) ->
    ?log("Unknown request: ~p", [Request]),
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
handle_info({tcp, Port, Data}, State = #state{qworker = Qworker}) ->
    ?log("(~p) received: ~p", [self(), Data]),
    Result = 
        case string:tokens(Data, " \r\n") of
            ["in", Arg | _] -> queue_worker:in(Qworker, Arg);
            ["out" | _ ]    -> queue_worker:out(Qworker);
            ["len" | _ ]    -> queue_worker:len(Qworker);
            []              -> "";
            _               -> unknown_command
        end,
    Output = case io_lib:printable_list(Result) of
        true  -> Result ++ "\r\n";
        false -> io_lib:format("~p\r\n", [Result])
    end,
    gen_tcp:send(Port, Output), 
    {noreply, State};

handle_info({tcp_closed, _Port}, State) ->
    ?log("(~p) received: tcp_closed", [self()]),
    session_mngr ! {session_worker, self(), tcp_closed},
    {noreply, State#state{qworker = undefined}};

handle_info(Info, State) ->
    ?log("(~p) received: ~p", [self(), Info]),
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
