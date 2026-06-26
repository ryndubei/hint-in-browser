import {
    ConsoleStdout,
    File,
    OpenFile,
    PreopenDirectory,
    Directory,
} from '@bjorn3/browser_wasi_shim';
import { DyLDBrowserHost, main } from "./ghc/dyld.mjs"
import { Terminal } from '@xterm/xterm'
import { openpty, Flags } from 'xterm-pty'
import { HS_SEARCH_DIR, MAIN_SO_PATH, MAIN_SO_BASE_NAME, CABAL_DYN_LIB_DIRS } from './generated/constants.mjs';

import './xterm.css';
import './index.css';

document.querySelector('#root').innerHTML = `
<div id="terminal"></div>
`;

const term = new Terminal()

term.open(document.getElementById('terminal'));

const { master, slave } = openpty();

term.loadAddon(master)

function set_echo(b) {
    const cfg = slave.ioctl('TCGETS')
    if ((cfg.ECHO_P) !== b) {
        slave.ioctl('TCSETS',
            {
                iflag: cfg.iflag,
                oflag: cfg.oflag,
                cflag: cfg.cflag,
                lflag: cfg.lflag ^ Flags.ECHO,
                cc: cfg.cc
            })
    }
}

set_echo(false)

slave.write('Hello from \x1B[1;3;31mxterm.js\x1B[0m\n')

const term_logger = Object.create(console)
term_logger.debug = function (data, cb) {
    console.debug(data)
    slave.write(`${data}\n`, cb)
}
term_logger.log = function (data, cb) {
    console.log(data)
    slave.write(`${data}\n`, cb)
}
term_logger.info = function (data, cb) {
    console.info(data)
    slave.write(`${data}\n`, cb)
}
term_logger.warn = function (data, cb) {
    console.warn(data)
    slave.write(`${data}\n`, cb)
}
term_logger.error = function (data, cb) {
    console.error(data)
    slave.write(`${data}\n`, cb)
}
term_logger.crash = function (data, cb) {
    console.error(data)
    slave.write(`${data}\n`, cb)
    throw new Error(`${data}`)
}

if (!"WebAssembly" in window) {
    term_logger.crash("No WebAssembly")
} else {
    term_logger.log("WebAssembly present")
}

const [[rootfs_stream1, rootfs_stream2], rootfsStreamLength] = await fetch("/rootfs.tar.zst")
    .then((r) => {
        console.log(r);
        return [r.body.tee(), r.headers.get('content-length')];
    });

term_logger.log("Fetching and extracting rootfs...")

const rootfs_extractor_worker = new Worker(new URL('./rootfs_extractor.mjs', import.meta.url));

rootfs_extractor_worker.postMessage(rootfs_stream2, [rootfs_stream2])

var progress = 0

slave.write(`0.0 /${(rootfsStreamLength / (1024 * 1024)).toFixed(1)}MiB`)
for await (const chunk of rootfs_stream1) {
    progress += chunk.length;
    slave.write(`\r${(progress / (1024 * 1024)).toFixed(1)}`)
}
slave.write('\n')
term_logger.log("rootfs.tar.zst downloaded")

// mutably convert the received rootfs back to a PreopenDirectory
// needed because worker thread messages lose the class methods
function objectToFs(rfs) {
    function go(m) {
        for (const k of m.keys()) {
            const ino = m.get(k)
            // is a directory
            if ('contents' in ino) {
                m.set(k, new Directory(go(ino.contents)))
                // is a file
            } else if ('data' in ino) {
                m.set(k, new File(ino.data))
            } else {
                term_logger.crash("objectToFs: unexpected structure")
            }
        }

        return m
    }

    return new PreopenDirectory("/", go(rfs.dir.contents))
}

const rootfs = await new Promise(res => {
    rootfs_extractor_worker.onmessage = msg => {
        if (msg.data.wasi_result === 0) {
            res(objectToFs(msg.data.rootfs))
        } else {
            term_logger.crash(`Failed to extract rootfs: ${msg.data.wasi_result}`)
        }
    }
})

term_logger.log("rootfs extracted")

if (document.readyState === "loading") {
    await new Promise((res) =>
        document.addEventListener("DOMContentLoaded", res, { once: true })
    );
}

term_logger.log("Initialising DyLDBrowserHost...")
try {
    const dyld = await main({
        rpc: new DyLDBrowserHost({
            rootfs,
            stdout: msg => term_logger.info(`${msg}`),
            stderr: msg => term_logger.warn(`${msg}`)
        }),
        searchDirs: [
            "/tmp/clib",
            HS_SEARCH_DIR,
            // "/tmp/hslib/lib/wasm32-wasi-ghc-9.14.0.20251031-inplace",
        ].concat(CABAL_DYN_LIB_DIRS),
        mainSoPath: MAIN_SO_PATH,
        args: [MAIN_SO_BASE_NAME, "+RTS", "-c", "-RTS"],
        // mainSoPath: "/tmp/libplayground001.so",
        // args: ["libplayground001.so", "+RTS", "-c", "-RTS"],
        isIserv: false,
    });

    term_logger.log("DyLDBrowserHost loaded")

    await dyld.exportFuncs.run_hint_in_browser();
} catch (err) {
    term_logger.error(`${err}`)
}

