#! /bin/bash

erl -pa apps/*/ebin -boot start_sasl -config apps/qserver/priv/qserver -s qs 

