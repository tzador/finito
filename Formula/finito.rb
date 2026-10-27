class Finito < Formula
  desc "Throw confetti across all your displays from the command-line"
  homepage "https://github.com/tzador/finito"
  url "https://github.com/tzador/finito/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "90d5e28bfa04fc82f064f2a543446d7ba5bce6e22155bae5cec1c317cb1dd265"
  license "MIT"
  head "https://github.com/tzador/finito.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/finito"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/finito --version")
  end
end
