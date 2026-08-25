/**
 * Hello OpenField plugin — minimal example.
 *
 * The runtime injects a global `of` object. Every privileged call is
 * promise-based and gated by the permissions declared in manifest.json.
 * Keep onLoad/onUnload as TOP-LEVEL functions: the host looks them up on
 * the global object after evaluating this file.
 */

async function onLoad() {
  of.log('hello-openfield loading');

  // Namespaced key-value storage (permission: storage).
  const seen = await of.storage.get('launches');
  const count = ((seen && Number(seen.value)) || 0) + 1;
  await of.storage.set('launches', count);

  // Short in-app banner (permission: ui.toast).
  await of.ui.toast('Hello! Launch #' + count);
  return true;
}

function onUnload() {
  of.log('hello-openfield unloading');
  return true;
}
