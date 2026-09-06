defmodule HelloLiveView.MilesightTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.Milesight

  test "parse_challenge/1 reads quoted and bare fields" do
    challenge = ~s(qop="auth", realm="IPNC", nonce="81e38536", stale="FALSE", algorithm=MD5)

    assert Milesight.parse_challenge(challenge) == %{
             "qop" => "auth",
             "realm" => "IPNC",
             "nonce" => "81e38536",
             "stale" => "FALSE",
             "algorithm" => "MD5"
           }
  end

  test "digest/7 answers the way RFC 2617's own example does" do
    challenge =
      Milesight.parse_challenge(
        ~s(realm="testrealm@host.com", qop="auth,auth-int", ) <>
          ~s(nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41")
      )

    authorization =
      Milesight.digest(
        challenge,
        "Mufasa",
        "Circle Of Life",
        "GET",
        "/dir/index.html",
        "0a4f113b"
      )

    assert authorization =~ ~s(response="6629fae49393a05397450978507c4ef1")
    assert authorization =~ ~s(username="Mufasa")
    assert authorization =~ ~s(qop=auth, nc=00000001, cnonce="0a4f113b")
    assert authorization =~ ~s(opaque="5ccc069c403ebaf9f0171e9517f40e41")
  end

  test "an unreachable host is an error, not a crash" do
    assert {:error, _reason} = Milesight.snapshot("127.0.0.1:9", "admin", "secret", timeout: 500)
  end

  # Against a real camera, when one is named in the environment:
  #   CAMERA_HOST=... CAMERA_USER=... CAMERA_PASSWORD=... mix test --include camera
  @tag :camera
  test "grabs a JPEG from the camera in CAMERA_HOST" do
    host = System.fetch_env!("CAMERA_HOST")
    user = System.fetch_env!("CAMERA_USER")
    password = System.fetch_env!("CAMERA_PASSWORD")

    assert {:ok, <<0xFF, 0xD8, _::binary>> = jpeg} = Milesight.snapshot(host, user, password)
    assert byte_size(jpeg) > 10_000
    assert Milesight.snapshot(host, user, password <> "-wrong") == {:error, :unauthorized}
  end
end
