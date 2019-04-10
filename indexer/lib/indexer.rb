require "date"
require "json"
require "set"
require "pathname"
require "pathname-glob"
require_relative "core_ext"
require_relative "card_sets_data"

require_relative "patches/patch"
Dir["#{__dir__}/patches/*.rb"].each do |path| require_relative path end

class Indexer
  ROOT = Pathname(__dir__).parent.parent + "data"

  # In verbose mode we validate each patch to make sure it actually does something
  def initialize(save_path, verbose=false)
    @save_path = Pathname(save_path)
    @verbose = verbose
    @data = CardSetsData.new
  end

  def json_normalize(data)
    if data.is_a?(Array)
      data.map do |elem|
        json_normalize(elem)
      end
    elsif data.is_a?(Hash)
      Hash[data.map{|k,v|
        [k, json_normalize(v)]
      }.sort]
    else
      data
    end
  end

  def call
    @save_path.parent.mkpath
    # Keep set index order as is, normalize eveything else
    index = prepare_index
    index["cards"] = json_normalize(index["cards"])
    index["sets"].each do |set_code, set|
      index["sets"][set_code] = set
    end
    @save_path.write(index.to_json)
  end

  private

  def prepare_index
    ### Prepare something for patches to be able to work with
    sets, cards = load_database

    ### Apply patches
    apply_patches(cards, sets)

    ### Return data for saving
    sets = sets.map{|s| [s["code"], index_set(s)]}.to_h
    set_order = sets.keys.each_with_index.to_h
    {
      "sets" => sets,
      "cards" => cards.map{|name, card_data|
        [name, index_card(card_data, set_order)]
      }.sort.to_h
    }
  end

  def index_set(set)
    set.slice(
      "block_code",
      "block_name",
      "booster",
      "border",
      "code",
      "custom",
      "foiling",
      "frame",
      "gatherer_code",
      "has_boosters",
      "name",
      "alternative_block_code",
      "alternative_code",
      "online_only",
      "release_date",
      "type",
    ).compact
  end

  def patches
    [
      # For transition period we support any mix of mtgjson v3 and v4
      PatchMtgjsonVersions,
      # Each set needs unique code, by convention all lowercase
      PatchSetCodes,
      PatchRemoveTokens,

      # All cards absolutely need unique numbers
      PatchMultipartCardNumbers,
      PatchFixCollectorNumbers,
      PatchUseFallbackNumbers,
      PatchBattlebond,
      PatchVerifyCollectorNumbers,

      # Normalize data into more convenient form
      PatchNormalizeRarity,
      PatchNormalizeColors,
      PatchLoyaltySymbol,
      PatchDisplayPowerToughness,
      PatchNormalizeReleaseDate,
      PatchManaCost,

      # Calculate extra fields
      PatchBlocks,
      PatchHasBoosters,
      PatchSecondary,
      PatchExcludeFromBoosters,
      PatchFunny,
      PatchLinkRelated,
      PatchPrintSheets,
      PatchFrame,
      PatchFoiling,

      # Reconcile issues
      PatchReconcileForeignNames,
      PatchAssignPrioritiesToSets,
      PatchReconcileOnSetPriority,
      PatchDeleteErrataSets,

      # Patch mtg.wtf bugs
      PatchSaga,
      PatchCmc,
      PatchNissa,
      PatchMediaInsertArtists,
      PatchCstdRarity,
      PatchWatermarks,
      PatchConspiracyWatermarks,
      PatchBasicLandRarity,
      PatchUnstableBorders,
      PatchEmnCardNumbers,
      PatchItpRqsRarity,
      PatchDeleteIncompleteCards,
      PatchAeLigature,
      PatchFlipCardManaCost,

      # Not bugs, more like different judgment calls than mtgjson
      PatchBfm,
      PatchUrza,
      PatchFixPromoPrintDates,
      PatchMeldCardNames,

      # One more round of normalization, it throws away some information
      PatchNormalizeNames,
    ]
  end

  def apply_patches(cards, sets)
    patches.each do |patch_class|
      if @verbose
        # This is very slow, and some patches are just here to verify things
        # It could still be useful for debugging
        before = Marshal.load(Marshal.dump([cards, sets]))
        patch_class.new(cards, sets).call
        if before == [cards, sets]
          warn "Patch #{patch_class} seems to be doing nothing"
        end
      else
        patch_class.new(cards, sets).call
      end
    end
  end

  def load_database
    sets = []
    cards = {}

    @data.each_set do |set_code, set_data|
      set = set_data.slice(
        "border",
        "custom",
        "name",
        "releaseDate",
        "type",
      ).merge(
        "mci_code" => set_data["magicCardsInfoCode"],
        "gatherer_code" => set_data["gathererCode"],
        "official_code" => set_data["code"],
        "online_only" => set_data["onlineOnly"],
        "booster" => set_data["booster"] || set_data["boosterV3"],
        # Track v3 vs v4 for migration
        "v4" => !!set_data["baseSetSize"],
      ).compact
      sets << set
      set_data["cards"].each_with_index do |card_data, i|
        name = card_data["name"]
        card_data["set"] = set
        (cards[name] ||= []) << card_data
      end
    end
    return sets, cards
  end

  def index_card(card, set_order)
    common_card_data = []
    printing_data = []
    card.each do |printing|
      common_card_data << printing.slice(
        "cmc",
        "colors",
        "display_power",
        "display_toughness",
        "foreign_names",
        "funny",
        "hand", # vanguard
        "hide_mana_cost",
        "layout",
        "life", # vanguard
        "loyalty",
        "manaCost",
        "name",
        "names",
        "power",
        "related",
        "reserved",
        "rulings",
        "secondary",
        "subtypes",
        "supertypes",
        "text",
        "toughness",
        "types",
      ).compact

      printing_data << [
        printing["set_code"],
        printing.slice(
          "artist",
          "border",
          "exclude_from_boosters",
          "flavor",
          "foiling",
          "frame",
          "multiverseid",
          "number",
          "print_sheet",
          "rarity",
          "release_date",
          "timeshifted",
          "watermark",
        ).compact
      ]
    end

    result = common_card_data[0]
    name = result["name"]
    # Make sure it's reconciled at this point
    # This should be hard error once we're done
    report_if_inconsistent(name, common_card_data, card)

    # Output in canonical form, to minimize diffs between mtgjson updates
    result["printings"] = printing_data.sort_by{|sc,d| [set_order.fetch(sc), d["number"], d["multiverseid"]] }
    result
  end

  def report_if_inconsistent(name, common_card_data, card)
    return if common_card_data.uniq.size == 1
    keys = common_card_data.map(&:keys).inject(&:|)
    inconsistent_keys = keys.select{|key| common_card_data.map{|ccd| ccd[key]}.uniq.size > 1 }
    warn "Data for card #{name} inconsistent on #{inconsistent_keys.join(", ")}"
    inconsistent_keys.each do |key|
      warn "* #{key}: #{card.map{|c| [c["set_code"], c[key]]}.inspect}"
    end
  end
end
