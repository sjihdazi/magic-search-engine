class PackController < ApplicationController
  def index
    @booster_types = $CardDatabase.supported_booster_types
    @title = "Packs"
  end

  def show
    set_code, variant = params.require(:id).downcase.split("-", 2)

    unless $CardDatabase.sets[set_code]
      render_404
      return
    end

    factory = PackFactory.new($CardDatabase)
    @pack = factory.for(set_code, variant)

    unless @pack
      render_404
      return
    end
  end
end
