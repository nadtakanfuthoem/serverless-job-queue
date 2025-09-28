/**
 * Background Job Processor
 * Processes messages from SQS queue with CloudWatch logging
 */
const { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');
const { CloudWatchLogsClient, CreateLogStreamCommand, PutLogEventsCommand } = require('@aws-sdk/client-cloudwatch-logs');
const { ulid } = require('ulid');

// Initialize AWS clients
const sqsClient = new SQSClient({
    region: process.env.AWS_REGION || 'us-east-1'
});

const cloudWatchLogsClient = new CloudWatchLogsClient({
    region: process.env.AWS_REGION || 'us-east-1'
});

// Configuration from environment
const QUEUE_URL = process.env.SQS_QUEUE_URL;
const LOG_GROUP_NAME = process.env.LOG_GROUP_NAME || '/ecs/message-driven-microservices-prod/background-job';

console.log('LOG_GROUP_NAME:', LOG_GROUP_NAME);

/**
 * Create a CloudWatch log stream for a job
 */
async function createJobLogStream(jobId) {
    const now = new Date();
    const dateString = now.toISOString().split('T')[0]; // YYYY-MM-DD
    const streamName = `job-streams/${dateString}/${jobId}`;
    
    try {
        await cloudWatchLogsClient.send(new CreateLogStreamCommand({
            logGroupName: LOG_GROUP_NAME,
            logStreamName: streamName
        }));
        console.log(`Created log stream: ${streamName}`);
        return streamName;
    } catch (error) {
        if (error.name === 'ResourceAlreadyExistsException') {
            console.log(`Log stream already exists: ${streamName}`);
            return streamName;
        }
        console.error('Error creating log stream:', error);
        throw error;
    }
}

/**
 * Write log entries to CloudWatch for a specific job
 */
async function writeJobLog(jobId, logStreamName, message, level = 'INFO') {
    try {
        const logEvent = {
            timestamp: Date.now(),
            message: JSON.stringify({
                jobId,
                level,
                message,
                timestamp: new Date().toISOString()
            })
        };

        await cloudWatchLogsClient.send(new PutLogEventsCommand({
            logGroupName: LOG_GROUP_NAME,
            logStreamName: logStreamName,
            logEvents: [logEvent]
        }));
    } catch (error) {
        console.error('Error writing to CloudWatch log:', error);
        // Don't throw here to avoid breaking job processing
    }
}

/**
 * Process a single message from the queue
 */
async function processMessage(message) {
    let jobId = null;
    let logStreamName = null;
    
    try {
        console.log('Processing message:', message.MessageId);
        
        // Parse the message body
        const messageBody = JSON.parse(message.Body);
        jobId = messageBody.jobId || ulid();
        
        console.log('Message content:', messageBody);
        console.log(`Processing job: ${jobId}`);
        
        // Create dedicated log stream for this job
        logStreamName = await createJobLogStream(jobId);
        
        // Log job start
        await writeJobLog(jobId, logStreamName, `Job started: ${messageBody.jobType}`, 'INFO');
        await writeJobLog(jobId, logStreamName, `Job data: ${JSON.stringify(messageBody.data)}`, 'INFO');
        
        console.log(`Processing job: ${messageBody.jobType}`);
        console.log(`Job data:`, messageBody.data);
        
        // Simulate processing work
        await writeJobLog(jobId, logStreamName, 'Processing job...', 'INFO');
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // Log successful completion
        await writeJobLog(jobId, logStreamName, 'Job completed successfully', 'INFO');
        console.log(`Job completed successfully: ${jobId}`);
        
        return true;
    } catch (error) {
        console.error('Error processing message:', error);
        
        // Log error if we have job info
        if (jobId && logStreamName) {
            await writeJobLog(jobId, logStreamName, `Job failed: ${error.message}`, 'ERROR');
        }
        
        throw error;
    }
}

/**
 * Delete processed message from queue
 */
async function deleteMessage(receiptHandle) {
    try {
        const deleteParams = {
            QueueUrl: QUEUE_URL,
            ReceiptHandle: receiptHandle
        };
        
        await sqsClient.send(new DeleteMessageCommand(deleteParams));
        console.log('Message deleted from queue');
    } catch (error) {
        console.error('Error deleting message:', error);
        throw error;
    }
}

/**
 * Poll for messages from SQS queue
 */
async function pollForMessages() {
    console.log('Polling for messages from queue:', QUEUE_URL);
    
    try {
        const receiveParams = {
            QueueUrl: QUEUE_URL,
            MaxNumberOfMessages: 10,
            WaitTimeSeconds: 20, // Long polling
            VisibilityTimeoutSeconds: 60
        };
        
        const command = new ReceiveMessageCommand(receiveParams);
        const response = await sqsClient.send(command);
        
        if (response.Messages && response.Messages.length > 0) {
            console.log(`Received ${response.Messages.length} messages`);
            
            // Process each message
            for (const message of response.Messages) {
                try {
                    await processMessage(message);
                    await deleteMessage(message.ReceiptHandle);
                } catch (error) {
                    console.error(`Failed to process message ${message.MessageId}:`, error);
                    // Message will become visible again after visibility timeout
                    // After maxReceiveCount, it will be moved to DLQ
                }
            }
        } else {
            console.log('No messages received');
        }
    } catch (error) {
        console.error('Error polling for messages:', error);
    }
}

/**
 * Main processing loop
 */
async function main() {
    console.log('Starting background job processor...');
    console.log('Queue URL:', QUEUE_URL);
    
    if (!QUEUE_URL) {
        console.error('SQS_QUEUE_URL environment variable not set');
        process.exit(1);
    }
    
    // Continuous polling
    while (true) {
        try {
            await pollForMessages();
        } catch (error) {
            console.error('Error in main loop:', error);
            // Wait before retrying
            await new Promise(resolve => setTimeout(resolve, 5000));
        }
    }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('Received SIGTERM, shutting down gracefully...');
    process.exit(0);
});

// Start the processor
if (require.main === module) {
    main().catch(error => {
        console.error('Fatal error:', error);
        process.exit(1);
    });
}

module.exports = { processMessage, deleteMessage, pollForMessages };
