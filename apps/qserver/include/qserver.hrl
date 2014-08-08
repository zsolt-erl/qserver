
-define(PORT, 2244).

-define(log(Msg), io:format("[~-20.20s] ~s~n", [?MODULE, Msg])).
-define(log(Format, Args), io:format("[~-20.20s] "++Format++"~n", [?MODULE]++Args)).

