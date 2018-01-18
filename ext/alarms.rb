
def get_alarm_envs (params)
  envs = []
  params.each do | key,value |
    if key.include? '.'
      envs << key.split('.').last
    end
  end
  return envs
end

def replace_vars(hash,find,replace)
  if hash.is_a?(Hash)
    hash.each do |k, v|
      replace_vars(v,find,replace)
    end
  elsif hash.is_a?(Array)
    hash.each do |e|
      replace_vars(e,find,replace)
    end
  elsif hash.is_a?(String) && hash == find
    hash.replace replace
  end
  hash
end

def create_param_mappings(params,template_envs,alarmHash)
  mappings = {}
  params.each do |key,value|
    if !key.include? '.'
      if [String, Integer, Float, Fixnum, TrueClass].member?(value.class)
        mappings[key] = {}
        template_envs.each do |env|
          if !params["#{key}.#{env}"].nil? && [String, Integer, Float, Fixnum, TrueClass].member?(params["#{key}.#{env}"].class)
            mappings[key][env] = params["#{key}.#{env}"]
          else
            mappings[key][env] = value
          end
        end
      end
    end
  end
  Mapping("#{alarmHash}", mappings)
end
