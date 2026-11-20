# The window

One window, two views: the form when no session runs, and the screen while one runs.

## The form

- The line to allow the viewer key on the machine (`viewer_key.md`).
- The address of the machine (`host:port`, the port 7101 when it is absent), its key (64 hexadecimal digits), the
  switch of the input, and the button Connect.
- The sentence of the last end, when a session ended.

The form checks the address and the key before it starts a connection, and names the field that is wrong.

## The screen

- The screen of the machine fills the room under a thin bar, scaled with its proportions, in the middle.
- The texture has the size of the screen. The window uploads only the damage that the connection published.
- The pointer of the machine is a ring at its place, over the screen. The service sends no picture of its pointer.
- The bar holds the address, the size of the screen, and the button Disconnect.

## The input

With the input on, while the session runs:

- A key press, its release and its character go to the machine as one `Key` record. The toolkit gives the key and its
  character as two events: the window joins a press with the `Text` event that follows it in the same batch.
- The modifiers Shift and Control go with each key. The contract carries no other modifier.
- The window maps each key of the toolkit to its scan code of set 1. A key with no code in the table does not go.
- A move, a press and a release of the left or the right button over the screen go as `Pointer` records, at the place
  on the screen of the machine. A wheel notch goes in the wheel of a pointer record.
- The events that go to the machine do not reach the interface. A press on the bar reaches it.

## The refused forms

- **The screen as an image widget of the toolkit.** The window needs the rectangle of the screen to map the pointer.
  A custom box gives it, and draws the texture and the ring in one call.
- **A key sent at its press, and its character later.** The contract carries both in one record, and the compositor
  of the machine reads them together.
