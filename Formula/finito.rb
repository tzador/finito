class Finito < Formula
  desc "Throw confetti across all your displays from the command-line"
  homepage "https://github.com/tzador/finito"
  url "https://github.com/tzador/finito/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "01997bf68e37f2144b45bea9c2a6a108b33e88d711c98209087af00e6929ac96"
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
