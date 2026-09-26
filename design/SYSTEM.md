# Postcard visual system

A photographic object on warm paper, with a small stamp and an expressive serif heading. The interface should feel like correspondence rather than a chat feed.

| Token | Value / intent |
|---|---|
| Paper | RGB 0.96, 0.94, 0.88 / background |
| Card | RGB 1.00, 0.985, 0.95 / postcard and fields |
| Ink | RGB 0.13, 0.25, 0.21 / text and primary controls |
| Muted | RGB 0.36, 0.39, 0.33 / supporting text |
| Vermilion | RGB 0.66, 0.22, 0.14 / stamp, errors, small accents |
| Rule | RGB 0.77, 0.77, 0.69 / decorative dividers, not essential content |
| Type | System serif for headings/messages; system sans for controls and labels |
| Spacing | 24-point screen inset; 18–28-point section rhythm; 8-point photo border |
| Shape | 4–8-point postcard corners; 10–16-point control corners |
| Touch | At least 44 points; primary buttons typically 52 points |

All essential text uses dynamic system text styles. Only decorative stamp lettering uses a small fixed size, and the decoration is hidden from accessibility. Supporting text is deliberately dark enough to read on paper. Screens use a consistent light-paper appearance even when the host app uses dark mode; document this product choice rather than silently inheriting low-contrast system surfaces.

## Screen intent

- **Front:** travel photo dominates. Destination and recipient sit on the paper beneath it. Open is the primary next step.
- **Writing:** recipient, spacious editable note, a live character count, and signature. Message content is never silently truncated.
- **Sealed:** vermilion seal, recipient summary, send and reopen. Editing requires reopening; sealing does not send.
- **Inbox:** correspondence cards grouped by person, a note excerpt, destination, and date. Excerpts can truncate because the full message is available in the conversation.
- **Conversation:** front/back postcard object with explicit Read their note / See photograph controls; complete selectable message text.
- **Authentication:** quiet editorial header and native secure inputs; validation and email confirmation are inline.

## Acceptance checks

Photo front, back, sealed, inbox, receiving, and auth must render at phone and wide widths. Controls remain reachable at accessibility text sizes and with the keyboard shown. No message disappears when offline; retries do not clear fields. Verify all callbacks in the fixture harness before connecting real services. Do not label stored messages as delivered/read.

## Measured text contrast

WCAG relative luminance calculations for the actual RGB tokens: ink/paper 9.96:1; muted/paper 5.43:1; vermilion/paper 5.63:1; card text/ink button 11.03:1; card text/vermilion seal 6.24:1. Decorative rules and disabled controls are not used to convey essential text.
