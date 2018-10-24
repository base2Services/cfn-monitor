module CfnMonitor
  class Utils

    # Merge Hash B into hash A. If any values or hashes as well, merge will be performed recursively
    # Returns Hash A with updated values
    def self.deep_merge(a, b)

      # Loop over key/value pairs
      b.each { |key, value|

        # If key from B present in map A
        if a.key? key

          # If both are hashes call recursively
          if (a[key].class == Hash and b[key].class == Hash)
            a[key] = deep_merge(a[key], value)
          else
            # Overwrite value with value from B
            a[key] = value
          end
        else
          # Add key from B
          a[key] = value
        end
      }

      # Return hash a
      return a
    end

  end
end

class Hash
  def without(*keys)
    dup.without!(*keys)
  end

  def without!(*keys)
    reject! { |key| keys.include?(key) }
  end
end
