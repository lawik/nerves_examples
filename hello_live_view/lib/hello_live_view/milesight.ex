defmodule HelloLiveView.Milesight do
  @moduledoc """
  Grabs a still from a Milesight IP camera.

  The camera serves a JPEG at `/snapshot.cgi` behind HTTP Digest
  authentication: the first request gets a 401 with a challenge, the second
  carries the answer. Both go through `:httpc`, which ships with OTP, so
  this needs nothing the firmware does not already have. A camera that asks
  for Basic authentication instead, or for none, is handled too.

  Nothing is kept here. `snapshot/4` takes the address and credentials each
  time and hands back the image bytes:

      {:ok, jpeg} = HelloLiveView.Milesight.snapshot("192.0.2.10", "admin", "secret")
  """

  @path "/snapshot.cgi"
  @timeout 4_000
  @connect_timeout 2_000

  @type option :: {:scheme, :http | :https} | {:timeout, timeout()}

  @doc """
  The latest image the camera at `host` gives `user`.

  `host` may carry a port (`"192.0.2.10:8080"`). Options: `:scheme`, which
  defaults to `:http`, and `:timeout` for each request, #{@timeout} ms.
  """
  @spec snapshot(String.t(), String.t(), String.t(), [option()]) ::
          {:ok, binary()} | {:error, term()}
  def snapshot(host, user, password, opts \\ []) do
    {:ok, _started} = Application.ensure_all_started(:inets)
    url = "#{Keyword.get(opts, :scheme, :http)}://#{host}#{@path}"

    with {:ok, 401, headers, _body} <- get(url, [], opts),
         {:ok, authorization} <- answer(headers, user, password),
         {:ok, 200, headers, body} <- get(url, [{"authorization", authorization}], opts) do
      image(headers, body)
    else
      {:ok, 200, headers, body} -> image(headers, body)
      {:ok, 401, _headers, _body} -> {:error, :unauthorized}
      {:ok, status, _headers, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The `Authorization` value answering a Digest challenge, as RFC 2617 has
  it for `qop=auth`, which is what the cameras use.

  `cnonce` and `nc` can be given so the answer can be checked against the
  RFC's own example; a real request takes a fresh `cnonce`.
  """
  @spec digest(map(), String.t(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
          String.t()
  def digest(challenge, user, password, method, uri, cnonce \\ cnonce(), nc \\ "00000001") do
    realm = Map.get(challenge, "realm", "")
    nonce = Map.get(challenge, "nonce", "")
    qop = if auth_qop?(challenge), do: "auth"

    ha1 = md5([user, ?:, realm, ?:, password])
    ha2 = md5([method, ?:, uri])

    response =
      if qop,
        do: md5([ha1, ?:, nonce, ?:, nc, ?:, cnonce, ?:, qop, ?:, ha2]),
        else: md5([ha1, ?:, nonce, ?:, ha2])

    fields =
      [username: user, realm: realm, nonce: nonce, uri: uri, response: response] ++
        if(qop, do: [qop: qop, nc: nc, cnonce: cnonce], else: []) ++
        for(
          {key, value} <- Map.take(challenge, ["opaque", "algorithm"]),
          do: {String.to_atom(key), value}
        )

    "Digest " <>
      Enum.map_join(fields, ", ", fn
        {key, value} when key in [:qop, :nc, :algorithm] -> "#{key}=#{value}"
        {key, value} -> ~s(#{key}="#{value}")
      end)
  end

  @doc "The fields of a Digest challenge, quoted or bare."
  @spec parse_challenge(String.t()) :: %{String.t() => String.t()}
  def parse_challenge(challenge) do
    ~r/(\w+)=(?:"([^"]*)"|([^,\s]+))/
    |> Regex.scan(challenge)
    |> Map.new(fn
      [_all, key, "", bare] -> {key, bare}
      [_all, key, quoted | _rest] -> {key, quoted}
    end)
  end

  # ------------------------------------------------------------------ private

  defp get(url, headers, opts) do
    timeout = Keyword.get(opts, :timeout, @timeout)
    request = {String.to_charlist(url), for({k, v} <- headers, do: {~c"#{k}", ~c"#{v}"})}
    http_opts = [timeout: timeout, connect_timeout: @connect_timeout, autoredirect: false]

    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_version, status, _reason}, headers, body}} ->
        {:ok, status, for({k, v} <- headers, do: {to_string(k), to_string(v)}), body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp answer(headers, user, password) do
    case List.keyfind(headers, "www-authenticate", 0) do
      {_name, value} ->
        case String.split(value, " ", parts: 2) do
          [scheme, challenge] -> answer(String.downcase(scheme), challenge, user, password)
          _other -> {:error, {:unsupported_authentication, value}}
        end

      nil ->
        {:error, :unauthorized}
    end
  end

  defp answer("digest", challenge, user, password) do
    challenge = parse_challenge(challenge)

    case Map.get(challenge, "algorithm", "MD5") do
      "MD5" -> {:ok, digest(challenge, user, password, "GET", @path)}
      other -> {:error, {:unsupported_algorithm, other}}
    end
  end

  defp answer("basic", _challenge, user, password),
    do: {:ok, "Basic " <> Base.encode64(user <> ":" <> password)}

  defp answer(scheme, _challenge, _user, _password),
    do: {:error, {:unsupported_authentication, scheme}}

  # The content type is trusted when it says image; a camera that sends
  # something else with a JPEG's magic bytes still counts.
  defp image(headers, <<0xFF, 0xD8, _rest::binary>> = body) when is_list(headers), do: {:ok, body}

  defp image(headers, body) do
    case List.keyfind(headers, "content-type", 0) do
      {_name, "image/" <> _} -> {:ok, body}
      _other -> {:error, :not_an_image}
    end
  end

  defp auth_qop?(challenge) do
    challenge
    |> Map.get("qop", "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.member?("auth")
  end

  defp md5(iodata), do: :crypto.hash(:md5, iodata) |> Base.encode16(case: :lower)
  defp cnonce, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
