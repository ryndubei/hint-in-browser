import {
    ConsoleStdout,
    File,
    OpenFile,
    PreopenDirectory,
    WASI,
} from '@bjorn3/browser_wasi_shim'

const rootfs = new PreopenDirectory("/", []);

const bsdtar_wasi = new WASI(
    ["bsdtar.wasm", "-x"],
    [],
    [
        new OpenFile(new File(new Uint8Array(), { readonly: true })),
        ConsoleStdout.lineBuffered((msg) => console.info(msg)),
        ConsoleStdout.lineBuffered((msg) => console.warn(msg)),
        rootfs,
    ],
    { debug: false }
);

const [{ instance }, rootfs_bytes] = await Promise.all([
    WebAssembly.instantiateStreaming(
        fetch("/bsdtar.wasm"),
        { wasi_snapshot_preview1: bsdtar_wasi.wasiImport }
    ),
    fetch("/rootfs.tar.zst").then((r) => r.bytes()),
]);

bsdtar_wasi.fds[0] = new OpenFile(
    new File(rootfs_bytes, { readonly: true })
);

const wasi_result = bsdtar_wasi.start(instance);

if (wasi_result === 0) {
    console.log("Rootfs extracted")

    postMessage(rootfs)
} else {
    throw new Error("Failed to extract rootfs")
}
