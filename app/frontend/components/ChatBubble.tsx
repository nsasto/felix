import React from "react";
import { Message, MessageRole } from "../types";
import { Bot as IconFelix, Terminal as IconTerminal } from "lucide-react";

interface ChatBubbleProps {
  message: Message;
}

const ChatBubble: React.FC<ChatBubbleProps> = ({ message }) => {
  const isUser = message.role === MessageRole.USER;

  return (
    <div className={`flex gap-4 ${isUser ? "flex-row-reverse" : "flex-row"}`}>
      <div
        className={`flex-shrink-0 w-8 h-8 rounded-lg flex items-center justify-center ${
          isUser ? "bg-slate-700" : "bg-brand-600 shadow-lg shadow-brand-900/20"
        }`}
      >
        {isUser ? (
          <span className="text-[10px] font-bold">ME</span>
        ) : (
          <IconFelix className="w-5 h-5 text-white" />
        )}
      </div>

      <div
        className={`flex flex-col flex-1 min-w-0 ${isUser ? "items-end" : "items-start"}`}
      >
        <div
          className={`relative px-4 py-3 rounded-2xl text-sm leading-relaxed max-w-full ${
            isUser
              ? "bg-slate-800 text-slate-100 border border-slate-700"
              : "bg-transparent text-slate-300"
          }`}
        >
          {message.type === "terminal" && (
            <div className="flex items-center gap-2 mb-2 text-slate-500 font-mono text-xs italic">
              <IconTerminal className="w-3 h-3" />
              <span>executing context command</span>
            </div>
          )}

          <div
            className={`whitespace-pre-wrap ${!isUser ? "font-sans" : "font-mono text-xs"}`}
          >
            {message.text}
          </div>

          {/* Display grounding sources if available */}
          {message.sources && message.sources.length > 0 && (
            <div className="mt-4 pt-3 border-t border-slate-800/50">
              <p className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mb-2">
                Sources:
              </p>
              <div className="flex flex-wrap gap-2">
                {message.sources.map((source, idx) => (
                  <a
                    key={idx}
                    href={source.uri}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[10px] px-2 py-1 bg-slate-800/80 border border-slate-700/50 rounded hover:text-brand-400 hover:border-brand-500/30 transition-all flex items-center gap-1.5"
                  >
                    <svg
                      className="w-2.5 h-2.5"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                    {source.title}
                  </a>
                ))}
              </div>
            </div>
          )}

          {message.isThinking && (
            <div className="mt-2 flex gap-1">
              <div className="w-1.5 h-1.5 bg-brand-500 rounded-full animate-bounce"></div>
              <div className="w-1.5 h-1.5 bg-brand-500 rounded-full animate-bounce [animation-delay:-0.15s]"></div>
              <div className="w-1.5 h-1.5 bg-brand-500 rounded-full animate-bounce [animation-delay:-0.3s]"></div>
            </div>
          )}
        </div>

        <span className="mt-1 text-[9px] text-slate-600 font-mono uppercase tracking-tighter">
          {new Date(message.timestamp).toLocaleTimeString([], {
            hour12: false,
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
          })}
        </span>
      </div>
    </div>
  );
};

export default ChatBubble;
