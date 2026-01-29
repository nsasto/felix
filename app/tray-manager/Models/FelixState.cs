using System;
using System.Text.Json.Serialization;

namespace FelixTrayManager.Models
{
    /// <summary>
    /// Represents the state of the Felix agent, deserialized from felix/state.json
    /// </summary>
    public class FelixState
    {
        /// <summary>
        /// The ID of the requirement currently being processed
        /// </summary>
        [JsonPropertyName("current_requirement_id")]
        public string? CurrentRequirementId { get; set; }

        /// <summary>
        /// The ID of the last run
        /// </summary>
        [JsonPropertyName("last_run_id")]
        public string? LastRunId { get; set; }

        /// <summary>
        /// The last operating mode (planning/building)
        /// </summary>
        [JsonPropertyName("last_mode")]
        public string? LastMode { get; set; }

        /// <summary>
        /// The outcome of the last iteration (success/error/blocked)
        /// </summary>
        [JsonPropertyName("last_iteration_outcome")]
        public string? LastIterationOutcome { get; set; }

        /// <summary>
        /// When the state was last updated
        /// </summary>
        [JsonPropertyName("updated_at")]
        public DateTime UpdatedAt { get; set; }

        /// <summary>
        /// Current iteration number
        /// </summary>
        [JsonPropertyName("current_iteration")]
        public int CurrentIteration { get; set; }

        /// <summary>
        /// Current status (running/stopped/idle/error)
        /// </summary>
        [JsonPropertyName("status")]
        public string? Status { get; set; }

        /// <summary>
        /// Number of validation retries attempted
        /// </summary>
        [JsonPropertyName("validation_retry_count")]
        public int ValidationRetryCount { get; set; }

        /// <summary>
        /// Description of blocked task, if any
        /// </summary>
        [JsonPropertyName("blocked_task")]
        public string? BlockedTask { get; set; }

        /// <summary>
        /// Checks if the agent is currently in a running state
        /// </summary>
        public bool IsRunning => 
            string.Equals(Status, "running", StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// Checks if the agent encountered an error
        /// </summary>
        public bool IsError => 
            string.Equals(LastIterationOutcome, "error", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(Status, "error", StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// Gets a friendly status message for display in tooltip
        /// </summary>
        public string GetStatusMessage()
        {
            if (IsError)
            {
                return BlockedTask != null 
                    ? $"Error: {BlockedTask}" 
                    : "Error occurred";
            }

            if (IsRunning && CurrentRequirementId != null)
            {
                return $"Running - {CurrentRequirementId} (Iteration {CurrentIteration})";
            }

            if (IsRunning)
            {
                return $"Running - Iteration {CurrentIteration}";
            }

            return "Stopped";
        }
    }
}
