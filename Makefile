.PHONY: compile clean release test

compile:
	./rebar compile

clean:
	./rebar clean

release:
	rm -rf ./rel/qsnode
	./rebar generate

test:
	./rebar eunit

