class Finito < Formula
  desc "Throw confetti across all your displays from the command-line"
  homepage "https://github.com/tzador/finito"
  url "https://github.com/tzador/finito/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "47402adca43b490c491544f15bd014f177dee6fa3241ec6af5ccc31dff448b99"
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
