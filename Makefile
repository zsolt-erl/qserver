.PHONY: compile clean release test

compile:
	./rebar compile

clean:
	./rebar clean

release:
	./rebar generate

test:
	./rebar eunit

