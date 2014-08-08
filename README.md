QServer
=======

Overview
--------
QServer is a simple fifo queue server. It accepts connections over a TCP port and provides a line oriented interface to read and write the queue. Each connection gets assigned its own queue. Queues are kept only in memory and destroyed when the client disconnects.

Installation
------------
```sh
git clone http://github.com/zsolt-erl/qserver.git
cd qserver
make
make test
make release
```

This will compile the qserver application and create a release under ```qserver/rel``` .

You can run it in the erlang shell with ```qserver/start.sh``` to see log output.

You can also run it in the background as an erlang node with ```rel/qsnode/bin/qsnode start``` .

Configuration
-------------
The config file is at ```priv/qserver.config``` .

You can change the IP address and port the server binds to (default is 0.0.0.0 : 2244).

You can also change the maximum number of queue workers and session workers. 

Since in this version each session has its own queue and each queue is managed by only one session therefore the above numbers (max_sessions, max_queues) should be the same. Later versions can implement one-to-many and/or many-to-many relations between sessions and queues.

Protocol
--------
Command        | Description
:--------------|:---------------
in Argument    | put the Argument into the queue |
out            | take the oldest element out of the queue |
len            | get the queue length
    
**out** on an empty queue will return **empty** as an answer

Example
-------
###on the server:
```sh
> ./start.sh
[session_mngr        ] Listening on: 2244
Eshell V5.10.4  (abort with ^G)
1> [session_mngr        ] Acceptor <0.46.0> is waiting for connection, <0.45.0>
1> [session_mngr        ] Accepted connection
1> [session_mngr        ] Acceptor <0.46.0> is waiting for connection, <0.45.0>
1> [session_mngr        ] got new connection
1> [session_worker      ] (<0.52.0>) received: "in 12\r\n"
1> [session_worker      ] (<0.52.0>) received: "in 33\r\n"
1> [session_worker      ] (<0.52.0>) received: "in hello\r\n"
1> [session_worker      ] (<0.52.0>) received: "len\r\n"
1> [session_worker      ] (<0.52.0>) received: "out\r\n"
1> [session_worker      ] (<0.52.0>) received: "out\r\n"
1> [session_worker      ] (<0.52.0>) received: "out\r\n"
1> [session_worker      ] (<0.52.0>) received: "out\r\n"
1> [session_worker      ] (<0.52.0>) received: tcp_closed
1> [session_mngr        ] session worker <0.52.0> lost connection
1> [queue_worker        ] (<0.51.0>) resetting
1> [session_worker      ] (<0.52.0>) resetting
```

###on the client:
```sh
> telnet localhost 2244
Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.
connected to qserver
in 12
ok
in 33
ok
in hello
ok
len
3
out
"12"
out
"33"
out
"hello"
out
empty
^]
telnet> q
Connection closed.
```
