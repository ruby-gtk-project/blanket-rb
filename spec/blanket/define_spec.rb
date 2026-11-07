# frozen_string_literal: true

# Ported from blanket/define.in (see lib/blanket/define.rb for the port's own
# note on why there is no Meson templating here).
#
# This is the display-free half: the sound catalogue and credits tables are
# plain data, so they are worth pinning without ever building a window.
RSpec.describe Blanket::Define do
  describe ".sound_uri" do
    it "builds a file:// URI under the bundled sounds directory" do
      expect(Blanket::Define.sound_uri("rain")).to(
        eq("file://#{Blanket::Define::SOUNDS_DIR}/rain.ogg"),
      )
    end
  end

  describe ".credits_list" do
    it "flattens a credits table into 'Name: works' lines" do
      table = {"Ada Lovelace" => ["Engine", "Notes"], "Alan Turing" => ["Machine"]}

      expect(Blanket::Define.credits_list(table)).to(
        eq(["Ada Lovelace: Engine, Notes", "Alan Turing: Machine"]),
      )
    end

    it "round-trips the port's own artist credits" do
      expect(Blanket::Define.credits_list(Blanket::Define::ARTISTS)).to(
        all(match(/\A.+: .+\z/)),
      )
    end
  end

  describe "SOUNDS" do
    it "names every category upstream ships" do
      expect(Blanket::Define::SOUNDS.map { |category| category[:name] }).to(
        contain_exactly("Nature", "Travel", "Interiors"),
      )
    end

    it "gives every sound a name and a title" do
      Blanket::Define::SOUNDS.each do |category|
        category[:sounds].each do |sound|
          expect(sound[:name]).to(be_a(String).and(satisfy { |n| !n.empty? }))
          expect(sound[:title]).to(be_a(String).and(satisfy { |t| !t.empty? }))
        end
      end
    end

    it "carries the same number of leaf sounds upstream's define.py lists" do
      total = Blanket::Define::SOUNDS.sum { |category| category[:sounds].length }

      expect(total).to(eq(12))
    end
  end

  describe "NOISES" do
    it "is pink noise and white noise, in that order" do
      expect(Blanket::Define::NOISES.map { |noise| noise[:name] }).to(
        eq(["pink-noise", "white-noise"]),
      )
    end
  end

  describe "APP_ID" do
    it "matches this port's reversed-domain identifier" do
      expect(Blanket::Define::APP_ID).to(eq("org.rubygtkproject.Blanket"))
    end
  end
end
