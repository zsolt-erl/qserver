%% main supervisor of the qserver application
%%
-module(qserver_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

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
    SessionMngr = ?CHILD(session_mngr, worker),
    SessionSup  = ?CHILD(session_sup, supervisor),
    QueueSup    = ?CHILD(queue_sup, supervisor),

    {ok, { {one_for_one, 5, 10}, [SessionMngr, SessionSup, QueueSup] } }.

