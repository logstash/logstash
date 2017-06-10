/**
 * Converts Ingest JSON to LS Grok.
 */
function ingest_pipeline_to_logstash(json) {

    function handle_on_failure_pipeline(on_failure_json) {

        return IngestConverter.create_tag_conditional("_grokparsefailure",
            IngestConverter.join_hash_fields(on_failure_json.map(map_processor))
        );
    }

    function map_processor(processor) {

        var filter_blocks = [];
        if (IngestGrok.has_grok(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("grok", IngestGrok.grok_hash(processor))
            );
            if (IngestConverter.has_on_failure(processor, IngestGrok.get_name())) {
                filter_blocks.push(
                    handle_on_failure_pipeline(IngestConverter.get_on_failure(processor, IngestGrok.get_name()))
                );
            }
        }
        if (IngestDate.has_date(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("date", IngestDate.date_hash(processor))
            )
        }
        if (IngestGeoIp.has_geoip(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("geoip", IngestGeoIp.geoip_hash(processor))
            )
        }
        if (IngestConvert.has_convert(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("mutate", IngestConvert.convert_hash(processor))
            );
        }
        if (IngestGsub.has_gsub(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("mutate", IngestGsub.gsub_hash(processor))
            );
        }
        if (IngestAppend.has_append(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("mutate", IngestAppend.append_hash(processor))
            );
        }
        if (IngestJson.has_json(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("json", IngestJson.json_hash(processor))
            );
        }
        if (IngestRename.has_rename(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("mutate", IngestRename.rename_hash(processor))
            );
        }
        if (IngestLowercase.has_lowercase(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("mutate", IngestLowercase.lowercase_hash(processor))
            );
        }
        if (IngestSet.has_set(processor)) {
            filter_blocks.push(
                IngestConverter.create_hash("mutate", IngestSet.set_hash(processor))
            );
        }
        return IngestConverter.join_hash_fields(filter_blocks);
    }

    return IngestConverter.filters_to_file([
            IngestConverter.filter_hash(
                IngestConverter.join_hash_fields(JSON.parse(json)["processors"].map(map_processor))
            )
        ]
    );
}
