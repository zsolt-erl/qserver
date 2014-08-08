-define(log(Msg), io:format("[~-20.20s] ~s~n", [?MODULE, Msg])).
-define(log(Format, Args), io:format("[~-20.20s] "++Format++"~n", [?MODULE]++Args)).


-define( conf(Par),
        fun()->
            {ok, Val}=application:get_env(qserver, Par),
            Val
        end()
       ).
