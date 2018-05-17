# heliumqa-processor
HeliumQA Matlab processor for Magphan

# configuration
```bash
$> cp config.json.sample config.json
```

The configuration for the `command` uses two variables `$SOURCE` and `$DESTINATION`.
They will be replaced with a dynamic path values like so `/path/to/folder/requests/:request_id`
and `/path/to/folder/requests/:request_id/results` respectively.

Example:

```json
{
  "host": "http://localhost:3000",
  "email": "user@example.com",
  "password": "password",
  "command": "perl dummy.pl $SOURCE $DESTINATION"
}
```
