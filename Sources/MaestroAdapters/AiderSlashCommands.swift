import Foundation
import MaestroCore

/// Aider 의 built-in 슬래시 명령 카탈로그.
///
/// Aider 는 Claude Code 와 달리 사용자/프로젝트 정의 슬래시 명령 시스템이 없음 →
/// 정적 built-in 만 노출. 명령어 변동 시 여기 갱신.
public enum AiderSlashCommands {
    public static let builtIns: [SlashCommand] = [
        SlashCommand(name: "add", description: "Add files to the chat", category: "built-in"),
        SlashCommand(name: "drop", description: "Remove files from the chat", category: "built-in"),
        SlashCommand(name: "diff", description: "Show diff of edits in last message", category: "built-in"),
        SlashCommand(name: "commit", description: "Commit edits made outside chat", category: "built-in"),
        SlashCommand(name: "undo", description: "Undo last git commit", category: "built-in"),
        SlashCommand(name: "clear", description: "Clear chat history", category: "built-in"),
        SlashCommand(name: "tokens", description: "Show current token usage", category: "built-in"),
        SlashCommand(name: "lint", description: "Lint and fix in-chat files", category: "built-in"),
        SlashCommand(name: "test", description: "Run tests, fix problems found", category: "built-in"),
        SlashCommand(name: "run", description: "Run a shell command, share output", category: "built-in"),
        SlashCommand(name: "web", description: "Scrape webpage, add to chat", category: "built-in"),
        SlashCommand(name: "map", description: "Print repo-map", category: "built-in"),
        SlashCommand(name: "ls", description: "List in-chat files", category: "built-in"),
        SlashCommand(name: "load", description: "Load chat history from file", category: "built-in"),
        SlashCommand(name: "save", description: "Save chat history to file", category: "built-in"),
        SlashCommand(name: "architect", description: "Switch to architect mode", category: "built-in"),
        SlashCommand(name: "code", description: "Switch to code mode", category: "built-in"),
        SlashCommand(name: "ask", description: "Ask without making code changes", category: "built-in"),
        SlashCommand(name: "help", description: "Ask questions about Aider usage", category: "built-in"),
        SlashCommand(name: "exit", description: "Exit the chat", category: "built-in"),
    ]
}
