%% session supervisor
%%
%% supervises all open sessions, a new child gets created for each connection (session)
%%
-module(session_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([])->
    SessionWorker = ?CHILD(session_worker, worker),

    {ok, { {simple_one_for_one, 5, 10}, [SessionWorker] } }.

start_child(Qworker)->
    supervisor:start_child(?MODULE, [Qworker]).
