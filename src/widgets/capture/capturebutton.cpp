// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2017-2019 Alejandro Sirgo Rica & Contributors

#include "capturebutton.h"
#include "utils/colorutils.h"

#include <QGraphicsDropShadowEffect>

CaptureButton::CaptureButton(QWidget* parent)
  : QPushButton(parent)
{
    init();
}

CaptureButton::CaptureButton(const QString& text, QWidget* parent)
  : QPushButton(text, parent)
{
    init();
}

CaptureButton::CaptureButton(const QIcon& icon,
                             const QString& text,
                             QWidget* parent)
  : QPushButton(icon, text, parent)
{
    init();
}

void CaptureButton::init()
{
    setCursor(Qt::ArrowCursor);
    setFocusPolicy(Qt::NoFocus);

    auto* dsEffect = new QGraphicsDropShadowEffect(this);
    dsEffect->setBlurRadius(4);
    dsEffect->setOffset(0, 1);
    dsEffect->setColor(QColor(40, 32, 12, 75));

    setGraphicsEffect(dsEffect);
}

QString CaptureButton::globalStyleSheet()
{
    return CaptureButton(nullptr).styleSheet();
}

QString CaptureButton::styleSheet() const
{
    const bool dark = ColorUtils::colorIsDark(m_mainColor);
    const QColor edge = dark ? m_mainColor.lighter(150) : m_mainColor.darker(140);
    const QColor hover = dark ? m_mainColor.lighter(120) : m_mainColor.darker(108);
    const QColor ink = dark ? QColor(Qt::white) : QColor(61, 53, 32);
    return QStringLiteral("CaptureButton { border: 1px solid %1; border-radius: 6px;"
                          "padding: 3px 8px; background-color: %2; color: %3; }"
                          "CaptureToolButton { padding: 0; }"
                          "CaptureButton:hover { background-color: %4; }"
                          "CaptureButton:pressed, CaptureToolButton:checked { border: 2px solid %3; }")
      .arg(edge.name(), m_mainColor.name(), ink.name(), hover.name());
}

void CaptureButton::setColor(const QColor& c)
{
    m_mainColor = c;
    setStyleSheet(styleSheet());
}

QColor CaptureButton::m_mainColor;
