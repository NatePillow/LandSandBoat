-----------------------------------------------------------------------
-- user_config.lua  —  EDIT THIS on a fresh install.
--
-- Single place for client-side settings you may need to change for your
-- setup. Returns a plain table; more options may be added here over time.
-----------------------------------------------------------------------
return {
    -- ================================================================
    -- Map server config HTTP service (used by the autobots/automog/
    -- autoequip addons to talk to the map server).
    -- ================================================================

    -- HOST: the IP/hostname where the map server is reachable FROM THIS
    -- machine (the machine running the FFXI client / Ashita). Rule of
    -- thumb: the same address you use in your FFXI client to reach the
    -- map server.
    --   - Same machine as server         -> '127.0.0.1'
    --   - Win VM on a Linux/host box
    --       - VirtualBox/QEMU NAT (def.)  -> '10.0.2.2'
    --       - VirtualBox bridged adapter  -> the host's LAN IP
    --       - VMware NAT                  -> '192.168.x.1' (varies)
    --   - A different physical machine    -> the server's LAN IP
    -- If unsure, run `route print 0.0.0.0` in the VM's cmd and take the
    -- Gateway column.
    HOST = '192.168.40.92',

    -- PORT: must match settings/singleplayer.lua CONFIG_HTTP_PORT on the
    -- server.
    PORT = 51220,

    -- Sanity check from THIS machine (should print "ok"):
    --   curl http://HOST:PORT/healthz
}
