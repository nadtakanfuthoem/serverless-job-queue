// Pure message-driven main job (no HTTP endpoints)
import { SQSClient, SendMessageCommand, ReceiveMessageCommand, DeleteMessageCommand } from '@aws-sdk/client-sqs';
import { ulid } from 'ulid';

class MessageDrivenMainJob {
    constructor() {
        this.sqsClient = new SQSClient({
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        this.inputQueueUrl = process.env.INPUT_QUEUE_URL; // Trigger queue
        this.outputQueueUrl = process.env.SQS_QUEUE_URL;   // Background job queue
        this.running = true;
        this.pollInterval = parseInt(process.env.POLL_INTERVAL_MS) || 5000;
    }

    // Process incoming trigger messages
    async processMainJobTrigger(message) {
        console.log('📨 Processing main job trigger:', message.MessageId);
        
        try {
            const messageBody = JSON.parse(message.Body);
            console.log('📋 Trigger details:', messageBody);

            // Generate job ID
            const jobId = ulid();
            
            // Process the main job logic
            const result = {
                jobId,
                triggerMessageId: message.MessageId,
                processedAt: new Date().toISOString(),
                result: 'main job completed',
                data: messageBody
            };

            console.log('✅ Main job processed:', result);

            // Send to background job queue if needed
            if (messageBody.triggerBackgroundJob !== false) {
                await this.sendBackgroundJob({
                    jobId,
                    jobType: 'main-job-processing',
                    timestamp: new Date().toISOString(),
                    data: {
                        originalTrigger: messageBody,
                        mainJobResult: result
                    }
                });
            }

            return result;

        } catch (error) {
            console.error('❌ Main job processing failed:', error);
            throw error;
        }
    }

    // Send background job message
    async sendBackgroundJob(jobData) {
        if (!this.outputQueueUrl) {
            console.log('⚠️ No output queue configured, skipping background job');
            return null;
        }

        try {
            const message = {
                jobId: jobData.jobId,
                jobType: jobData.jobType,
                timestamp: jobData.timestamp,
                data: jobData.data
            };

            const command = new SendMessageCommand({
                QueueUrl: this.outputQueueUrl,
                MessageBody: JSON.stringify(message),
                MessageAttributes: {
                    jobType: {
                        DataType: 'String',
                        StringValue: message.jobType
                    },
                    jobId: {
                        DataType: 'String',
                        StringValue: message.jobId
                    }
                }
            });

            const result = await this.sqsClient.send(command);
            console.log('📤 Background job queued:', message.jobId);
            return result.MessageId;

        } catch (error) {
            console.error('❌ Failed to queue background job:', error);
            throw error;
        }
    }

    // Poll for trigger messages
    async pollForTriggers() {
        if (!this.inputQueueUrl) {
            console.log('⚠️ No input queue configured, running in standalone mode');
            
            // Generate synthetic triggers for demo
            await this.processMainJobTrigger({
                MessageId: `synthetic-${ulid()}`,
                Body: JSON.stringify({
                    trigger: 'synthetic',
                    timestamp: new Date().toISOString(),
                    triggerBackgroundJob: true
                }),
                ReceiptHandle: 'synthetic-handle'
            });
            return;
        }

        try {
            const receiveParams = {
                QueueUrl: this.inputQueueUrl,
                MaxNumberOfMessages: 5,
                WaitTimeSeconds: 20,
                VisibilityTimeoutSeconds: 60
            };

            const command = new ReceiveMessageCommand(receiveParams);
            const response = await this.sqsClient.send(command);

            if (response.Messages && response.Messages.length > 0) {
                console.log(`📥 Received ${response.Messages.length} trigger messages`);

                for (const message of response.Messages) {
                    try {
                        await this.processMainJobTrigger(message);
                        
                        // Delete processed message
                        await this.sqsClient.send(new DeleteMessageCommand({
                            QueueUrl: this.inputQueueUrl,
                            ReceiptHandle: message.ReceiptHandle
                        }));
                        
                        console.log('🗑️ Trigger message deleted');
                        
                    } catch (error) {
                        console.error('❌ Failed to process trigger:', error);
                    }
                }
            } else {
                console.log('💤 No trigger messages available');
            }

        } catch (error) {
            console.error('❌ Error polling for triggers:', error);
        }
    }

    // Start the message-driven processor
    async start() {
        console.log('🚀 Starting message-driven main job processor...');
        console.log('📮 Input queue:', this.inputQueueUrl || 'Not configured (synthetic mode)');
        console.log('📤 Output queue:', this.outputQueueUrl || 'Not configured');
        console.log('⏱️ Poll interval:', this.pollInterval, 'ms');

        while (this.running) {
            try {
                await this.pollForTriggers();
                
                // Wait before next poll
                if (this.inputQueueUrl) {
                    // Real queue polling doesn't need artificial delay
                    await new Promise(resolve => setTimeout(resolve, 1000));
                } else {
                    // Synthetic mode needs longer delays
                    await new Promise(resolve => setTimeout(resolve, this.pollInterval));
                }

            } catch (error) {
                console.error('💥 Main loop error:', error);
                await new Promise(resolve => setTimeout(resolve, 5000));
            }
        }
    }

    // Graceful shutdown
    stop() {
        console.log('🛑 Stopping main job processor...');
        this.running = false;
    }
}

// Create and start the processor
const processor = new MessageDrivenMainJob();

// Handle graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully...');
    processor.stop();
    setTimeout(() => process.exit(0), 1000);
});

process.on('SIGINT', () => {
    console.log('SIGINT received, shutting down gracefully...');
    processor.stop();
    setTimeout(() => process.exit(0), 1000);
});

// Start processing
processor.start().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
});
