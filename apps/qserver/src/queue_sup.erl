%% queue supervisor
%%
%% supervises the queue processes
%%
-module(queue_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/0]).

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
    QueueWorker = ?CHILD(queue_worker, worker),

    {ok, { {simple_one_for_one, 5, 10}, [QueueWorker] } }.

start_child()->
    supervisor:start_child(?MODULE, []).
