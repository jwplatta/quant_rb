class AddSampleColumn < ActiveRecord::Migration[8.0]
  def up
    add_column :option_chain_history, :sample, :boolean, default: false
  end

  def down
    remove_column :option_chain_history, :sample
  end
end
