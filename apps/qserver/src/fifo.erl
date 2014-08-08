%% FIFO queue implementation

-module(fifo).

-export([new/0, in/2, out/1, len/1]).

-type fifo() :: {fifo, Ref :: reference(), Elements :: [any()]}.


-spec new() -> fifo() .
new()-> {fifo, erlang:make_ref(), []}.


-spec in(Element :: any(), Queue :: fifo()) -> fifo() .
in(NewElem, {fifo, Ref, List}) -> {fifo, Ref, List ++ [NewElem]}.


-spec out(Queue :: fifo()) -> {Elem :: any(), fifo()} | empty .
out( {fifo, _, []} )            -> empty;
out( {fifo, Ref, [Head|Tail]} ) -> {Head, {fifo, Ref, Tail}}.

-spec len(fifo()) -> non_neg_integer() .
len( {fifo, _, List} ) -> length(List).

