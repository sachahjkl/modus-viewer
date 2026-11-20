// What the viewer is to the toolkit's update package (gt:update, docs/update.md of gui_toolkit): its name in the
// manifests and the release's file names, what its signatures cover, and the public half of its update key
// (`viewertool update keygen`; the private half is in secrets/production.yaml, encrypted with sops, and in the secret
// UPDATE_SIGNING_KEY of the release workflow). The program checks with it (updates.odin); the tool signs with it
// (`viewertool package`).
package viewer_update

import update "gt:update"

PRODUCT :: update.Product {
	name         = "modus-viewer",
	sign_context = "modus-viewer-update-v1\n",
	public_key   = "XgkURUxBoreC1cbHorCsM26ThDTc-An306mu0WNUx5g",
}
