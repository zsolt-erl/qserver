-module(qs).

-export([start/0, stop/0]).

start()->
    application:start(qserver).

stop()->
    application:stop(qserver).


