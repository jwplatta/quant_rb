class AddIndexOnSampleColumn < ActiveRecord::Migration[8.0]
  def up
    add_index :option_chain_history, :sample
  end

  def down
    remove_index :option_chain_history, :sample
  end
end
