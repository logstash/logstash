# encoding: utf-8

java_import "org.logstash.secret.store.SecretStoreExt"

module ::LogStash::Util::SubstitutionVariables

  include LogStash::Util::Loggable

  SUBSTITUTION_PLACEHOLDER_REGEX = /\${(?<name>[a-zA-Z_.][a-zA-Z0-9_.]*)(:(?<default>[^}]*))?}/

  # Recursive method to replace substitution variable references in parameters
  def deep_replace(value)
    if value.is_a?(Hash)
      value.each do |valueHashKey, valueHashValue|
        value[valueHashKey.to_s] = deep_replace(valueHashValue)
      end
    else
      if value.is_a?(Array)
        value.each_index do | valueArrayIndex|
          value[valueArrayIndex] = deep_replace(value[valueArrayIndex])
        end
      else
        return replace_placeholders(value)
      end
    end
  end

  # Replace all substitution variable references in the 'value' param and returns the substituted value, or the original value if a substitution can not be made
  # Process following patterns : ${VAR}, ${VAR:defaultValue}
  # If value matches the pattern, returns the following precedence : Secret store value, Environment entry value, default value as provided in the pattern
  # If the value does not match the pattern, the 'value' param returns as-is
  def replace_placeholders(value)
    return value unless value.is_a?(String)

    secret_store_config = SecretStoreExt.getConfig(LogStash::SETTINGS.get_setting("keystore.file").value, LogStash::SETTINGS.get_setting("keystore.classname").value)

    org.logstash.common.SubstitutionVariables.replacePlaceholders(
        value, ENV, secret_store_config
    );
  rescue org.logstash.common.SubstitutionVariables::MissingSubstitutionVariableError => e
    raise ::LogStash::ConfigurationError, e.getMessage
  end # def replace_placeholders
end
