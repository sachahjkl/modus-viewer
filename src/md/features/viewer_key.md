# The viewer key

The viewer proves itself to the machine with an Ed25519 key, in the handshake of TLS, as a client of `remote` does. A
principal of the machine allows its public key with `remote_display_allow`. The machine knows no other name of the
viewer.

## Where it is kept

- The private key is 32 random bytes from the generator of the operating system: `/dev/urandom` on Linux and macOS,
  `BCryptGenRandom` on Windows (`src/connection/system_random_*.odin`). If the system gives no bytes, the viewer
  makes no key and no connection, and says so; a fixed key or seed never takes their place.
- It is sealed with `gt:secrets` for the account of the user: the Secret Service on Linux, DPAPI on Windows. The
  viewer writes the sealed field in the file `viewer_key` of its configuration folder. The file never holds the key
  in clear.
- At each start, a worker reads the file and opens the field. With no file, it draws a key, seals it, and writes the
  file. The window gets the result, then shows the public key.
- If the store of secrets is absent, or refuses the seal, the key lives in memory for this run only, and the window
  says so. A key in clear on the disk is refused: whoever reads the file sees the screen that the key sees.
- If the file holds a field that the store cannot open (a locked keyring, another account), the viewer draws no new
  key: a new key would need a new allow on each machine. It says why, and connects with a key of this run only.

## What the window shows

The line to type in a console of the machine, with the public key in it:
`remote_display_allow("<public key>", "view_and_input")`. The public key is not a secret.

## The key for a program

`modus-viewer -print-key` prints the public key of the kept key on the standard output, with no window, and ends with
0. A program that allows the viewer before it connects reads it there, as `modustool run --remote-display` does
(`test_machine.md`). It reads and seals the key on its one thread: there is no window to keep responsive.

- A key of this run only is refused, with its sentence and the code 1: the key would be gone when the viewer starts
  again to connect, and the allow would name a key that nobody holds.
- A program never gets the private key: the viewer prints the public key only.
