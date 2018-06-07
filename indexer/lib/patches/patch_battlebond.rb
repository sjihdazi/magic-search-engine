# Gatherer creates those duplicates for partner cards
# and mtgjson just repeats that
# https://github.com/mtgjson/mtgjson/issues/586
# https://github.com/mtgjson/mtgjson/issues/587
# https://github.com/mtgjson/mtgjson/issues/588
class PatchBattlebond < Patch
  def call
    @cards.each do |name, printings|
      printings.delete_if do |printing|
        printing["set_code"] == "bbd" and printing["number"] =~ /b/
      end
    end

    patch_set do |set|
      next unless set["code"] == "bbd"
      set["type"] = set["type"].downcase
    end

    patch_card do |card|
      next unless card["set_code"] == "bbd"
      card["layout"] = "normal"
      if card["number"] =~ /a/
        card["number"].sub!(/a/,"")
        card.delete("names")
      end
    end
  end
end
