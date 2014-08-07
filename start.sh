#! /bin/bash

erl -pa apps/*/ebin -boot start_sasl -s qserver

