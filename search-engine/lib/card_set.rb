class CardSet
  attr_reader :name, :code, :alternative_code
  attr_reader :block_name, :block_code, :alternative_block_code
  attr_reader :border, :release_date, :printings, :types
  attr_reader :decks, :base_set_size
  attr_reader :products, :subsets
  attr_reader :normalized_name, :normalized_name_alt

  def initialize(db, data)
    @db = db
    @name          = data["name"]
    @code          = data["code"]
    @alternative_code = data["alternative_code"]
    @block_name    = data["block_name"]
    @block_code    = data["block_code"]&.downcase
    @alternative_block_code = data["alternative_block_code"]&.downcase
    @border        = data["border"]
    @types         = data["types"]
    @release_date  = data["release_date"] && Date.parse(data["release_date"])
    @printings     = Set[]
    @online_only   = !!data["online_only"]
    @has_boosters  = !!data["has_boosters"]
    @in_other_boosters = !!data["in_other_boosters"]
    @custom        = !!data["custom"]
    @funny         = !!data["funny"]
    @decks         = []
    @base_set_size = data["base_set_size"]
    @products = (data["products"] || []).map{|x| Product.new(self, x)}
    @subsets = data["subsets"]

    # cache for better performance of e:
    @normalized_name = normalize_set_name(@name)
    @normalized_name_alt = normalize_set_name_alt(@name)
  end

  def has_individual_card_release_dates?
    @printings.any?{|c| c.release_date != @release_date}
  end

  def individual_card_release_dates
    @printings.map(&:release_date).minmax
  end

  def cards_in_precons
    @db.cards_in_precons[@code]
  end

  def has_boosters?
    @has_boosters
  end

  def in_other_boosters?
    @in_other_boosters
  end

  def online_only?
    @online_only
  end

  def custom?
    !!@custom
  end

  def funny?
    !!@funny
  end

  # counting MH1 in addition to core sets and expansions
  def regular?
    @types.include?("standard") or @types.include?("modern")
  end

  include Comparable
  def <=>(other)
    @code <=> other.code
  end

  def hash
    @code.hash
  end

  def deck_named(name)
    @decks.find{|d| d.name == name}
  end

  def physical_cards(foil=false)
    @printings
      .select do |card|
        if foil
          card.foiling != "nonfoil"
        else
          card.foiling != "foilonly"
        end
      end
      .map do |card|
        PhysicalCard.for(card, foil)
      end
      .uniq
  end

  def physical_card_names
    [*physical_cards(true), *physical_cards(false)].map(&:name).uniq
  end

  def physical_cards_in_boosters(foil=false)
    physical_cards(foil).select(&:in_boosters?)
  end

  def inspect
    "CardSet[#{@code}, #{@name}]"
  end

  private
  # copied from CardDatabase
  def normalize_text(text)
    text.downcase.normalize_accents.strip
  end

  def normalize_name(name)
    normalize_text(name).split.join(" ")
  end

  def normalize_set_name(name)
    normalize_text(name).downcase.gsub("'s", "s").split(/[^a-z0-9]+/).join(" ")
  end

  def normalize_set_name_alt(name)
    normalize_text(name).downcase.gsub("'s", "").split(/[^a-z0-9]+/).join(" ")
  end
end
