import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Vector "mo:base/Vector";

actor AIAssistant {
    // Types
    type ChatMessage = {
        role: Text;
        content: Text;
        timestamp: Int;
    };

    type Task = {
        id: Text;
        description: Text;
        status: TaskStatus;
        created: Int;
        updated: Int;
    };

    type TaskStatus = {
        #pending;
        #inProgress;
        #completed;
        #failed;
    };

    type LLMConfig = {
        modelName: Text;
        maxTokens: Nat;
        temperature: Float;
        topP: Float;
    };

    // State
    private stable var messageHistoryEntries : [(Text, ChatMessage)] = [];
    private var messageHistory = HashMap.HashMap<Text, ChatMessage>(0, Text.equal, Text.hash);
    private var tasks = HashMap.HashMap<Text, Task>(0, Text.equal, Text.hash);
    private stable var nextTaskId: Nat = 0;
    private var authorizedUsers = HashMap.HashMap<Principal, Bool>(0, Principal.equal, Principal.hash);

    // LLM Configuration
    private let llmConfig : LLMConfig = {
        modelName = "llama-3.1-8b";
        maxTokens = 1024;
        temperature = 0.7;
        topP = 0.9;
    };

    // Initialize LLM connection
    private let llmCanister = actor "rrkah-fqaaa-aaaaa-aaaaq-cai" : actor {
        generate : shared (Text, Nat, Float, Float) -> async Text;
    };

    // Chat Functions
    public shared(msg) func sendMessage(content: Text) : async Result.Result<ChatMessage, Text> {
        if (not isAuthorized(msg.caller)) {
            return #err("Unauthorized access");
        };

        let userMessage: ChatMessage = {
            role = "user";
            content = content;
            timestamp = Time.now();
        };

        let messageId = Int.toText(userMessage.timestamp);
        messageHistory.put(messageId, userMessage);

        try {
            let llmResponse = await processWithLLM(content);
            
            let assistantMessage: ChatMessage = {
                role = "assistant";
                content = llmResponse;
                timestamp = Time.now();
            };

            let responseId = Int.toText(assistantMessage.timestamp);
            messageHistory.put(responseId, assistantMessage);
            #ok(assistantMessage)
        } catch (e) {
            #err("Error processing message with LLM")
        }
    };

    // Task Management
    public shared(msg) func createTask(description: Text) : async Result.Result<Task, Text> {
        if (not isAuthorized(msg.caller)) {
            return #err("Unauthorized access");
        };

        let taskId = Nat.toText(nextTaskId);
        nextTaskId += 1;

        let newTask: Task = {
            id = taskId;
            description = description;
            status = #pending;
            created = Time.now();
            updated = Time.now();
        };

        tasks.put(taskId, newTask);
        #ok(newTask)
    };

    public shared(msg) func getTask(taskId: Text) : async Result.Result<Task, Text> {
        if (not isAuthorized(msg.caller)) {
            return #err("Unauthorized access");
        };

        switch (tasks.get(taskId)) {
            case (?task) { #ok(task) };
            case null { #err("Task not found") };
        }
    };

    public shared(msg) func updateTaskStatus(taskId: Text, status: TaskStatus) : async Result.Result<Task, Text> {
        if (not isAuthorized(msg.caller)) {
            return #err("Unauthorized access");
        };

        switch (tasks.get(taskId)) {
            case (?task) {
                let updatedTask: Task = {
                    id = task.id;
                    description = task.description;
                    status = status;
                    created = task.created;
                    updated = Time.now();
                };
                tasks.put(taskId, updatedTask);
                #ok(updatedTask)
            };
            case null { #err("Task not found") };
        }
    };

    // LLM Processing
    private func processWithLLM(input: Text) : async Text {
        try {
            let prompt = "You are a helpful AI assistant. User input: " # input;
            let response = await llmCanister.generate(
                prompt,
                llmConfig.maxTokens,
                llmConfig.temperature,
                llmConfig.topP
            );
            return response;
        } catch (e) {
            Debug.print("Error calling LLM: " # debug_show(e));
            return "I apologize, but I encountered an error processing your request. Please try again.";
        }
    };

    // Authorization
    private func isAuthorized(caller: Principal) : Bool {
        switch (authorizedUsers.get(caller)) {
            case (?authorized) { authorized };
            case null { false };
        }
    };

    // Admin Functions
    public shared(msg) func addAuthorizedUser(user: Principal) : async Result.Result<(), Text> {
        if (msg.caller == Principal.fromActor(AIAssistant)) {
            authorizedUsers.put(user, true);
            #ok(())
        } else {
            #err("Unauthorized")
        }
    };

    // Query Functions
    public query func getChatHistory() : async [ChatMessage] {
        Iter.toArray(messageHistory.vals())
    };

    public query func getAllTasks() : async [Task] {
        Iter.toArray(tasks.vals())
    };

    // System Functions
    system func preupgrade() {
        messageHistoryEntries := Iter.toArray(messageHistory.entries());
    };

    system func postupgrade() {
        messageHistory := HashMap.fromIter<Text, ChatMessage>(
            messageHistoryEntries.vals(),
            messageHistoryEntries.size(),
            Text.equal,
            Text.hash
        );
        messageHistoryEntries := [];
    };
}