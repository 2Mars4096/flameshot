// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2017-2019 Alejandro Sirgo Rica & Contributors

#include "accepttool.h"

#include <QApplication>
#include <QPainter>
#include <QStyle>
#if defined(Q_OS_MACOS)
#include "widgets/capture/capturewidget.h"
#include <QWidget>
#include <QDir>
#include <QMessageBox>
#include <QProcess>
#include <QTemporaryFile>
#endif

AcceptTool::AcceptTool(QObject* parent)
  : AbstractActionTool(parent)
{}

bool AcceptTool::closeOnButtonPressed() const
{
    return true;
}

QIcon AcceptTool::icon(const QColor& background, bool inEditor) const
{
    Q_UNUSED(inEditor)
    return QIcon(iconPath(background) + "accept.svg");
}

QString AcceptTool::name() const
{
    return tr("Accept");
}

CaptureTool::Type AcceptTool::type() const
{
    return CaptureTool::TYPE_ACCEPT;
}

QString AcceptTool::description() const
{
    return qEnvironmentVariableIsSet("STICKY_TODO_CAPTURE")
             ? tr("Use screenshot in Sticky Todo")
             : tr("Accept the capture");
}

CaptureTool* AcceptTool::copy(QObject* parent)
{
    return new AcceptTool(parent);
}

void AcceptTool::pressed(CaptureContext& context)
{
#ifdef Q_OS_MACOS
    if (context.request.tasks() == CaptureRequest::NO_TASK) {
        QTemporaryFile png(QDir::temp().filePath("sticky-todo-capture-XXXXXX.png"));
        if (!png.open() || !context.selectedScreenshotArea().save(&png, "PNG") || !png.flush()) {
            QMessageBox::warning(nullptr, tr("Send to Todo"), tr("Could not prepare the selected image."));
            return;
        }
        png.close();
        const QString name = QFileInfo(png.fileName()).fileName();
        const QString link = "todo-sticky://flameshot/" + name;
        if (QProcess::execute("/usr/bin/open", {"-a", "/Applications/Sticky Todo.app", link}) != 0) {
            QMessageBox::warning(nullptr, tr("Send to Todo"), tr("Could not open Sticky Todo."));
            return;
        }
        png.setAutoRemove(false); // The receiving application consumes and removes the private PNG.
    }
#endif
    emit requestAction(REQ_CAPTURE_DONE_OK);
    if (context.request.tasks() & CaptureRequest::PIN) {
        QRect geometry = context.selection;
        geometry.moveTopLeft(geometry.topLeft() + context.widgetOffset);
        context.request.addTask(CaptureRequest::PIN);
    }
    emit requestAction(REQ_CLOSE_GUI);
}
