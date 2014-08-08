-module(fifo_tests).

-include_lib("eunit/include/eunit.hrl").

create_test()->
    ?assertMatch({fifo, _, []}, fifo:new()).

operations_test()->
    List = [a,b,c,d,e],
    %% push all elements into queue
    Qfull = lists:foldl( fun fifo:in/2, fifo:new(), List ),
    ?assertEqual( length(List), fifo:len(Qfull) ),

    %% take out as much as the length of the original list
    {ElementsOut, Qempty} = lists:foldl( 
            fun(_, {OutAcc, Queue}) -> 
                    {Elem, NewQ} = fifo:out(Queue),
                    {OutAcc ++ [Elem], NewQ}
            end,
            {[], Qfull},
            lists:seq(1, length(List)) ),
        
    ?assertEqual(List, ElementsOut),
    ?assertEqual(0, fifo:len(Qempty)),
    ?assertEqual(empty, fifo:out(Qempty)).
