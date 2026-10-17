extends Node

## Placeholder only: networking, replication, authority and authentication are
## not implemented. Do not use this as a production server.

const DEFAULT_PORT: int = 2456


func _ready() -> void:
    var port := _get_server_port()
    print("AshenKingdoms dedicated-server scaffold.")
    print("Configured port: %d. Network session logic is not implemented yet." % port)


func _get_server_port() -> int:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--server-port="):
            var value := argument.trim_prefix("--server-port=")
            if value.is_valid_int():
                return clampi(value.to_int(), 1, 65535)
    return DEFAULT_PORT
