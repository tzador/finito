class Finito < Formula
  desc "Throw confetti across all your displays from the command-line"
  homepage "https://github.com/tzador/finito"
  url "https://github.com/tzador/finito/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "22f1ffb1756076f8236fefd23572206daa445d89c8513c99d7996f6e4f577981"
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
