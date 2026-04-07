# frozen_string_literal: true

# Loader for seeds
def load_seed(name)
  file = File.read(Rails.root.join('db', 'seeds', "#{name}.yml"))
  erb = ERB.new(file).result
  YAML.safe_load(erb)
end
