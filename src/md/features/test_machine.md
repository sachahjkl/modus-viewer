# A test machine of modus

`viewertool machine <port> <machine key>` builds the viewer, then starts it with the address `127.0.0.1:<port>`, the
machine key, and the input on. It is the shortest path from a machine that the tool of modus runs to a viewer on it.

## What the tool of modus gives today

- `modustool run` starts the machine under QEMU. Its network device goes to the peer of the tool (`-netdev dgram`),
  not to the network of the host: no datagram of the host reaches the machine by itself.
- The peer has a UDP relay (`tools/modustool/machine/peer_relay.odin`): a socket on the loopback of the host whose
  datagrams go to the machine as datagrams from 10.0.2.2, the one address that the listen grant of `remote_display`
  admits. Its destination is the port of `quic_echo`, 4433, and `run` does not print the port of the relay.
- The machine starts `remote_display` when a console types `start("remote_display")`. The service then writes its
  public key on the log: `remote_display: the public key of this service: <key>`.

## What the tool of modus must give

- A relay to the UDP port 7101 of `remote_display` in the peer of `modustool run`, and its port on the terminal.

That change is in the modus repository, outside this one. Until it exists, the command connects to any port that the
user gives, and the machine does not answer.

## The steps of a session

1. `modustool run` in the modus repository.
2. In a console of the machine: `start("remote_display")`. Read the public key of the service on the log.
3. `viewertool machine <relay port> <public key of the service>`.
4. In a console of the machine: the line that the viewer shows, `remote_display_allow("<viewer key>", "view_and_input")`.
5. Connect again in the viewer: the first try ended with the sentence of a key that no principal allowed.
