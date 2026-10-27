class Finito < Formula
  desc "Blow autumn leaves across all your displays from the command-line"
  homepage "https://github.com/tzador/finito"
  url "https://github.com/tzador/finito/archive/refs/tags/v0.6.0.tar.gz"
  sha256 "21b90c22c71abf10e0356db9407c62f209dd277176c37aa79628b7302f4f8775"
  license "MIT"
  head "https://github.com/tzador/finito.git", branch: "main"

  depends_on "rust" => :build
  depends_on macos: :ventura

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/finito --version")
  end
end
