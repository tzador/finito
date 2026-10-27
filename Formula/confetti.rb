class Confetti < Formula
  desc "Throw confetti across all your displays from the command-line"
  homepage "https://github.com/tzador/confetti"
  url "https://github.com/tzador/confetti/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/tzador/confetti.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/confetti"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/confetti --version")
  end
end
