
def get_alarm_envs (params)
  envs = []
  params.each do | key,value |
    if key.include? 'Threshold'
      if key.include? '.'
        envs << key.split('.').last
      end
    end
  end
  return envs
end
