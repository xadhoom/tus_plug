defmodule TusPlug.Config do
  @moduledoc """
  Default config for TusPlug
  """
  defstruct upload_baseurl: "/files",
            upload_path: "/tmp",
            version: "1.0.0",
            max_body_read: 8_000_000,
            body_read_len: 1_000_000,
            # 4GByte max upload
            max_size: 4_294_967_296,
            # callbacks
            on_complete: nil
end
