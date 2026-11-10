class DesignKitsController < ApplicationController
  def index
    @design_kits = Current.workspace.design_kits.order(:name)
  end

  def create
    kit = Current.workspace.design_kits.create!(kit_params)
    redirect_to design_kits_path, notice: "Design kit created."
  rescue ActiveRecord::RecordInvalid => error
    render plain: error.record.errors.full_messages.join(". "), status: :unprocessable_entity
  end

  def update
    Current.workspace.design_kits.find(params[:id]).update!(kit_params)
    redirect_to design_kits_path, notice: "Design kit updated. Existing versions keep their styling."
  rescue ActiveRecord::RecordInvalid => error
    render plain: error.record.errors.full_messages.join(". "), status: :unprocessable_entity
  end

  private

  def kit_params
    params.require(:design_kit).permit(:name, tokens: %i[font background foreground accent])
  end
end
