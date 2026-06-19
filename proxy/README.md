# Proxy patched nixes

This contains patched versions of Nix and Lix that make it possible to run `nix-daemon` as a proxy for testing daemon protocol code.

For that to work 3 things need to be supported:
- `remoteProgram` option in SSH store
- `processOps` argument to `nix-daemon`
- No `dumpPath` in `nix-daemon`

When all these things are supported this will still make a `proxy_<nix>` package for that version of Nix/Lix it will just point to the normal package. 


## `remoteProgram` workaround in SSH store

The `remoteProgram` option can be used to call a local program to forward the daemon trafic to. For this to work the `remoteProgram` option needs to be present as well as the direct call of `remoteProgram` when the host is `localhost`.


## `--process-ops` argument to `nix-daemon`

We need to force the `nix-daemon` to process the ops in the protocol.

When the store is not local Nix and Lix has a performance inhancement that will just forward the streams instead of proccessing the ops itself.

This kind of defeats the purpose of the proxy approach and so we need a way around it.

At some point Nix added a `--process-ops` argument (though it is behind an experimental feature flag) and porting that (without the experimental feature flag) seemed the best option.


## No `dumpPath` in `nix-daemon`

Most versions of Nix and Lix use `dumpPath` in `nix-daemon` to implement `NarFromPath` which will try and read from the file system. The more correct approach is to use the `narFromPath` method of the store.