
import { GoogleGenAI, Type, GenerateContentResponse } from "@google/genai";
import { Message, MessageRole, ModelType, ContextFile } from "../types";

export class GeminiService {
  // Removed private ai: GoogleGenAI; from class member to ensure it's initialized with latest key per request if needed

  async generateResponse(
    model: ModelType,
    history: Message[],
    currentPrompt: string,
    attachments: any[] = [],
    contextFiles: ContextFile[] = [],
    useSearch: boolean = false
  ) {
    // Initialize GoogleGenAI right before the call as per guidelines
    const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
    const parts: any[] = [];
    
    // Inject context from "loaded" files
    if (contextFiles.length > 0) {
      let fileContext = "CURRENT WORKSPACE CONTEXT:\n";
      contextFiles.forEach(f => {
        fileContext += `File: ${f.path}\nContent:\n${f.content}\n---\n`;
      });
      parts.push({ text: fileContext });
    }

    attachments.forEach(att => {
      parts.push({
        inlineData: {
          mimeType: att.mimeType,
          data: att.data.split(',')[1] || att.data
        }
      });
    });

    parts.push({ text: currentPrompt });

    const config: any = {
      systemInstruction: `You are Felix, a senior-level AI technical orchestrator. 
      Your goal is to help users manage their coding workflow. 
      You are concise, professional, and focus on providing executable solutions.
      - When asked to write code, provide high-quality, documented snippets.
      - When suggesting terminal commands, wrap them clearly.
      - You can 'see' the user's workspace context provided in the conversation.
      - Use markdown for technical responses.`,
      // Correct thinking budget for Gemini 3 models
      thinkingConfig: model === ModelType.PRO ? { thinkingBudget: 4000 } : undefined
    };

    if (useSearch) {
      config.tools = [{ googleSearch: {} }];
    }

    const contents = history.map(msg => ({
      role: msg.role === MessageRole.USER ? 'user' : 'model',
      parts: [{ text: msg.text }]
    }));

    contents.push({
      role: 'user',
      parts: parts
    });

    try {
      const response: GenerateContentResponse = await ai.models.generateContent({
        model: model,
        contents: contents,
        config: config
      });

      // Extract sources from groundingMetadata as required by guidelines
      const sources = response.candidates?.[0]?.groundingMetadata?.groundingChunks?.map((chunk: any) => ({
        title: chunk.web?.title || "Reference",
        uri: chunk.web?.uri || "#"
      })).filter((s: any) => s.uri !== "#") || [];

      return { 
        text: response.text || "No response generated.",
        sources: sources
      };
    } catch (error) {
      console.error("Gemini API Error:", error);
      throw error;
    }
  }
}

export const geminiService = new GeminiService();
