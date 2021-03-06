-module(queue_worker).

-include("qserver.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0, reset/1, in/2, out/1, len/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
        fifo = fifo:new()
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

reset(WorkerPid)->
    gen_server:call(WorkerPid, reset).

in(WorkerPid, Element) ->
    gen_server:call(WorkerPid, {in, Element}).
    
out(WorkerPid) ->
    gen_server:call(WorkerPid, out).

len(WorkerPid) ->
    gen_server:call(WorkerPid, len).

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
    session_mngr ! {self(), queue_worker_ready},
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
    Reply = ok,
    NewState = State#state{fifo = fifo:new()},
    {reply, Reply, NewState};

handle_call(len, _From, State) ->
    Reply = fifo:len(State#state.fifo),
    {reply, Reply, State};

handle_call({in, Element}, _From, State = #state{fifo = Fifo}) ->
    NewFifo  = fifo:in(Element, Fifo),
    NewState = State#state{fifo = NewFifo},
    Reply = ok,
    {reply, Reply, NewState};

handle_call(out, _From, State = #state{fifo = Fifo}) ->
    {Reply, NewState} = 
        case fifo:out(Fifo) of 
            empty          -> {empty, State};
            {Out, NewFifo} -> {Out, State#state{fifo = NewFifo}}
        end,
    {reply, Reply, NewState};

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
handle_info(_Info, State) ->
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
