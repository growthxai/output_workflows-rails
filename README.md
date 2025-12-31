# Output Workflows for Rails

> **Alpha Release** - This gem is currently for GrowthX internal use only.

Rails SDK for the Output.ai AI & APIs framework. This SDK supports both synchronous (wait for result) and asynchronous (background polling) execution, as well as webhook-based execution.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "output_workflows-rails", github: "growthxai/output_workflows-rails", require: "output_workflows"
```

And then execute:

```bash
bundle install
```

### Rails Setup

Run the generator to create the migration and initializer:

```bash
rails generate output_workflows:install
rails db:migrate
```

## Structure

SDK structure:

```
lib/output_workflows/
├── client.rb                    # Main HTTP client - all workflow operations
├── configuration.rb             # ENV-based configuration
├── error.rb                     # Custom exceptions
├── webhook_verifier.rb          # HMAC-SHA256 signature verification
├── responses/
│   ├── status.rb               # Workflow status (running, completed, etc)
│   └── workflow_result.rb      # Workflow output/result
└── rails/
    ├── workflow_execution.rb   # ActiveRecord for tracking (with progress)
    ├── status_check_job.rb     # Background polling
    ├── webhook_processor.rb    # Base processor class
    ├── progress_processor.rb   # Updates execution progress
    └── railtie.rb              # Rails integration
```

## Configuration

Uses environment variables:

```bash
OUTPUT_API_URL=https://api.output.ai    # Required in production
OUTPUT_WEBHOOK_SECRET=<your-secret>     # For webhook signature verification
```

Defaults to `http://localhost:2000` in development/test.

### Ruby Configuration

```ruby
# config/initializers/output_workflows.rb
OutputWorkflows.configure do |config|
  config.api_url = ENV["OUTPUT_API_URL"]
  config.api_key = ENV["OUTPUT_API_KEY"]
  config.webhook_secret = ENV["OUTPUT_WEBHOOK_SECRET"]

  # Polling configuration
  config.default_timeout = 300      # 5 minutes
  config.default_poll_interval = 5  # 5 seconds

  # Rails integration
  config.job_queue = :default
  config.table_name = "output_workflow_executions"
  config.max_progress_entries = 100
end
```

### Generating a Webhook Secret

Generate a secure secret for both dev and production:

```bash
# Using OpenSSL (recommended)
openssl rand -hex 32

# Using Ruby
ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"

# Using Rails
rails secret | head -c 64
```

**Important:** The same secret must be configured in both:
1. Your Rails app (`OUTPUT_WEBHOOK_SECRET` env var)
2. Your Output.ai workflow settings (so it signs webhooks)

## Use Cases

### 1. Webhooks (Recommended)

Output.ai calls your endpoint when workflows complete. No polling, instant notifications, efficient.

**Complete end-to-end flow:**

```
1. Your app starts workflow → Output.ai
2. Output.ai runs workflow (async)
3. Output.ai sends webhook → Your endpoint
4. Your app processes results
```

**Step 1: Start the workflow**

```ruby
# In your controller, background job, or service
class BrandsController < ApplicationController
  def analyze
    brand = Brand.find(params[:id])

    # Start workflow on Output.ai
    client = OutputWorkflows::Client.new
    workflow_id =
      client.start_workflow(
        "myAnalysisWorkflow",
        {
          identifier: brand.id, # Pass your model ID so webhook can find it
          url: brand.url,
          data: brand.to_workflow_input,
        },
      )

    # Store workflow_id for reference (optional)
    brand.update!(workflow_id: workflow_id, status: :analyzing)

    redirect_to brand, notice: "Analysis started"
  end
end
```

**Step 2: Receive webhook when complete**

```ruby
# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def output
    # Verify signature from Output.ai
    verifier = OutputWorkflows::WebhookVerifier.new(ENV.fetch("OUTPUT_WEBHOOK_SECRET"))
    verifier.verify!(request.raw_post, request.headers["X-Signature"])

    # Store webhook (process in background job)
    Webhook.create!(payload: request.request_parameters, source: :output)
    head :ok
  rescue OutputWorkflows::WebhookVerifier::VerificationError => e
    Rails.logger.warn "Webhook signature verification failed: #{e.message}"
    head :unauthorized
  end
end
```

**Step 3: Process the results**

```ruby
# app/models/webhook/output/my_analysis_processor.rb
class Webhook::Output::MyAnalysisProcessor
  def initialize(webhook_payload)
    @payload = webhook_payload
  end

  def process
    # payload.action = "my_analysis"
    # payload.identifier = brand.id (what you passed in step 1)
    # payload.my_analysis = { result: "...", score: 95, ... }

    brand = Brand.find(@payload.identifier)
    brand.update!(
      analysis_result: @payload.my_analysis.result,
      analysis_score: @payload.my_analysis.score,
      status: :completed,
    )

    # Send notification, trigger next steps, etc.
    BrandAnalysisMailer.complete(brand).deliver_later
  end
end
```

### 2. Asynchronous: Background Polling

**When to use:** You can't receive webhooks.

**How it works:** Start a workflow, save execution record to DB, background job polls 5 seconds until complete.

**Why track in database?**

- Monitor all running workflows in one place
- Retry failed workflows
- Audit trail of all executions
- Query workflow history

**Setup: Run the generator**

```bash
rails generate output_workflows:install
rails db:migrate
```

**Usage:**

```ruby
# Start workflow
client = OutputWorkflows::Client.new
workflow_id = client.start_workflow("myWorkflow", args)

# Create execution record (tracks workflow state in your DB)
execution =
  OutputWorkflows::Rails::WorkflowExecution.create!(
    workflow_name: "myWorkflow",
    workflow_id: workflow_id,
    input_params: args,
    status: :pending,
  )

# Background job polls Output.ai every 5 seconds, updates execution record
OutputWorkflows::Rails::StatusCheckJob.perform_later(execution.id)

# Later: check status in your DB (no API call needed)
execution.reload
execution.status # :pending, :running, :completed, :failed
execution.error_message # Error details if failed
execution.completed_at # When it finished

# Note: Output data is NOT stored in the execution record.
# Request output via fetch_output! and extract to your domain models.
```

#### Why don't we store output data in the execution record?

The `output_workflow_executions` table stores **execution metadata only**:

**Why?** This design enforces proper domain modeling:

1. **Executions are ephemeral** - The table can be purged regularly without losing business data
2. **Forces domain thinking** - You must extract relevant data to your actual domain models (User, Product, etc.)
3. **Prevents abuse** - The executions table is for logging, replay, and debugging - not data storage

**How to get workflow output:**

1. Request it from the Output.ai API using the client methods (`fetch_output!`, `wait_for_completion!`)
2. Extract the data you need from the response
3. Store it in your proper domain models

**Example:**

```ruby
execution = OutputWorkflows::Rails::WorkflowExecution.find(id)
output = execution.fetch_output! # Requests from Output.ai API
MyModel.find(identifier).update!(result: output["some_field"], processed_at: Time.current)
```

### 3. Synchronous: Wait for Result

Ideal for scripts, debugging, or sequential processing where blocking is acceptable:

```ruby
client = OutputWorkflows::Client.new

# Start and wait (blocks until complete)
workflow_id = client.start_workflow("myWorkflow", { data: "..." })
result = client.wait_for_completion(workflow_id)

# Access output - NOTE: Not stored in database, extract to your domain models
result.output # The actual workflow data
result.workflow_id # For reference

# Example: Extract to domain model
MyModel.find(identifier).update!(processed_data: result.output["some_field"], status: :completed)
```

## Quick Tutorial

### Starting a Workflow

```ruby
client = OutputWorkflows::Client.new

workflow_id =
  client.start_workflow(
    "myResearchWorkflow",
    { url: "https://example.com", identifier: "abc-123", categories: Category.to_workflow_input },
  )
# => "workflow-id-12345"
```

### Checking Status

```ruby
status = client.workflow_status(workflow_id)

status.running? # true/false
status.completed? # true/false
status.failed? # true/false
status.status_name # "RUNNING", "COMPLETED", etc
```

### Getting the Result

```ruby
# Option 1: Wait (blocking)
result = client.wait_for_completion(workflow_id, timeout: 300)

# Option 2: Fetch when done
result = client.workflow_result(workflow_id, run_id)

# Access data
result.output # Hash with workflow output
result.to_json # Serialize everything
```

### Error Handling

```ruby
begin
  result = client.wait_for_completion(workflow_id)
rescue OutputWorkflows::TimeoutError
  # Exceeded timeout
rescue OutputWorkflows::WorkflowFailedError => e
  # Workflow failed
  puts e.status_name # "FAILED", "TERMINATED", etc
rescue OutputWorkflows::APIError => e
  # HTTP/network error
  puts e.response_status
end
```

## Common Patterns

### Sequential Processing

```ruby
items.each do |item|
  workflow_id = client.start_workflow("process", item: item)
  result = client.wait_for_completion(workflow_id)
  item.update!(processed_data: result.output)
end
```

### Batch with Tracking

```ruby
items.each do |item|
  workflow_id = client.start_workflow("process", item: item)

  OutputWorkflows::Rails::WorkflowExecution.create!(
    workflow_name: "process",
    workflow_id: workflow_id,
    input_params: {
      item_id: item.id,
    },
    status: :running,
  )
end

# Background jobs poll and update as they complete
```

### Workflow Executions and Exacutable

Link executions to any model:

```ruby
class MyModel < ApplicationRecord
  has_one :workflow_execution,
          as: :executable,
          class_name: "OutputWorkflows::Rails::WorkflowExecution"

  def handle_workflow_completion(execution)
    # Called automatically when workflow completes
    output = execution.fetch_output!
    update!(processed_data: output["result"])
  end
end

# Create linked execution
execution = OutputWorkflows::Rails::WorkflowExecution.create!(
  workflow_name: "myWorkflow",
  workflow_id: workflow_id,
  executable: my_model
)
```

### Monitoring

```ruby
# Check what's running
OutputWorkflows::Rails::WorkflowExecution.active.each do |execution|
  puts "#{execution.workflow_name}: #{execution.status}"
end

# Cleanup old records
OutputWorkflows::Rails::WorkflowExecution.purge_old(days: 30)
```

## Progress Tracking

Workflow executions support real-time progress tracking via webhooks.

### Progress Column

The `progress` column stores a JSONB array of progress updates:

```json
[
  { "name": "Processing Batch 1", "extra_info": "keyword 1 of 100", "at": "2024-12-07T21:30:00Z" },
  { "name": "Processing Batch 1", "extra_info": "keyword 50 of 100", "at": "2024-12-07T21:30:05Z" },
  { "name": "Analyzing Results", "extra_info": "generating insights", "at": "2024-12-07T21:31:00Z" }
]
```

### How It Works

1. **Workflow sends progress webhooks** with action `workflow_progress`:
   ```json
   {
     "action": "workflow_progress",
     "workflowId": "wf_abc123",
     "name": "Processing Batch 1",
     "extraInfo": "keyword 45 of 100"
   }
   ```

2. **Processor updates execution** (non-blocking, lossy OK):
   ```ruby
   # Using the built-in processor
   OutputWorkflows::Rails::ProgressProcessor.new(payload).process
   ```
   - Caps at 100 entries (configurable via `max_progress_entries`)
   - Progress is for real-time display, not audit logs

3. **Auto-truncate on completion**:
   - Progress array can be cleared when workflow completes/fails
   - Keeps table lean (progress is only useful while active)

### Displaying Progress

```ruby
execution = OutputWorkflows::Rails::WorkflowExecution.find_by(workflow_id: "wf_abc123")

# Get latest progress
if execution.progress.any?
  latest = execution.progress.first  # Most recent is first
  puts "#{latest['name']}: #{latest['extra_info']}"
end

# Or iterate through timeline
execution.progress.each do |entry|
  puts "[#{entry['at']}] #{entry['name']} - #{entry['extra_info']}"
end
```

## Webhook Integration

Output.ai sends webhooks for workflow events like progress updates. The gem provides processors to handle these webhooks.

### Controller Setup

```ruby
# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def output
    verify_signature!
    process_webhook!
    head :ok
  rescue OutputWorkflows::WebhookVerifier::VerificationError
    head :unauthorized
  end

  private

  def verify_signature!
    OutputWorkflows::WebhookVerifier.new(
      OutputWorkflows.configuration.webhook_secret
    ).verify!(request.raw_post, request.headers["X-Signature"])
  end

  def process_webhook!
    payload = JSON.parse(request.raw_post)

    case payload["action"]
    when "workflow_progress"
      OutputWorkflows::Rails::ProgressProcessor.new(payload).process
    else
      Rails.logger.warn "Unknown webhook action: #{payload['action']}"
    end
  end
end
```

```ruby
# config/routes.rb
post "/webhooks/output", to: "webhooks#output"
```

### Built-in Processors

**ProgressProcessor** handles `workflow_progress` webhooks:

```ruby
# Automatically updates execution.progress array
OutputWorkflows::Rails::ProgressProcessor.new(payload).process
```

Expected payload format:
```json
{
  "action": "workflow_progress",
  "workflowId": "wf-123",
  "name": "Processing step 1",
  "extraInfo": "Optional details"
}
```

### Custom Processors

Create custom processors by subclassing `WebhookProcessor`:

```ruby
class MyCustomProcessor < OutputWorkflows::Rails::WebhookProcessor
  def process
    # Access payload data
    puts workflow_id  # payload["workflowId"]
    puts action       # payload["action"]
    puts execution    # WorkflowExecution record

    # Your custom logic here
  end
end
```

### Async Processing (Recommended for Production)

For production, process webhooks asynchronously:

```ruby
# app/controllers/webhooks_controller.rb
def output
  verify_signature!
  Webhook.create!(payload: JSON.parse(request.raw_post))
  head :ok
end

# app/models/webhook.rb
class Webhook < ApplicationRecord
  after_create_commit :process_async

  def process!
    case payload["action"]
    when "workflow_progress"
      OutputWorkflows::Rails::ProgressProcessor.new(payload).process
    end
  end

  private

  def process_async
    WebhookProcessJob.perform_later(id)
  end
end
```

## API Reference

### OutputWorkflows::Client

```ruby
client = OutputWorkflows::Client.new(api_url: "...", api_key: "...")

client.start_workflow(name, args, **opts) # → workflow_id
client.workflow_status(workflow_id) # → Status object
client.workflow_result(workflow_id, run_id) # → WorkflowResult
client.wait_for_completion(workflow_id, **opts) # → WorkflowResult (blocks)
client.cancel_workflow(workflow_id) # → Boolean
```

### OutputWorkflows::Rails::WorkflowExecution

```ruby
execution = OutputWorkflows::Rails::WorkflowExecution.create!(...)

execution.status              # :pending, :running, :completed, :failed
execution.terminal?           # completed or failed?
execution.active?             # pending or running?
execution.progress            # Array of progress updates (JSONB)
execution.poll_status!        # Update from API
execution.wait_for_completion! # Block until done
execution.fetch_output!       # Get output from API
execution.cancel!             # Cancel workflow
execution.append_progress!    # Add progress entry
```

### OutputWorkflows::Rails::WebhookProcessor

Base class for webhook processing:

```ruby
processor = OutputWorkflows::Rails::WebhookProcessor.new(payload)

processor.payload      # Normalized Hash (string keys)
processor.workflow_id  # payload["workflowId"]
processor.action       # payload["action"]
processor.execution    # WorkflowExecution record (or nil)
processor.process      # Override in subclasses
```

### OutputWorkflows::Rails::ProgressProcessor

Handles `workflow_progress` webhooks:

```ruby
processor = OutputWorkflows::Rails::ProgressProcessor.new(payload)
processor.process  # Updates execution.progress, sets status to :running
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
